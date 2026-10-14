/*
    BIKEZ - VALIDACION DEL DATA WAREHOUSE (FASE 1)
    Ejecutar en SQL Server Management Studio.
    NO MODIFICA DATOS: solo sentencias SELECT.
    Para comparar con el origen, deben existir BikeZ y BikeZDW.

    Este script fue ajustado al esquema real creado en 01_Creacion_BikeZDW.sql.
    No usa claves surrogate ficticias (Key) porque el modelo final usa IDs reales
    de DW con nombres como ClienteID, ProductoID, EmpleadoID, TerritorioID.
*/
USE BikeZDW;
GO

SET NOCOUNT ON;

-- 1. Cantidad de registros por tabla
SELECT 'Dim_Tiempo' AS Tabla, COUNT(*) AS Registros FROM dbo.Dim_Tiempo
UNION ALL
SELECT 'Dim_Cliente', COUNT(*) FROM dbo.Dim_Cliente
UNION ALL
SELECT 'Dim_Producto', COUNT(*) FROM dbo.Dim_Producto
UNION ALL
SELECT 'Dim_Empleado', COUNT(*) FROM dbo.Dim_Empleado
UNION ALL
SELECT 'Dim_Territorio', COUNT(*) FROM dbo.Dim_Territorio
UNION ALL
SELECT 'Fact_Detalle_Venta', COUNT(*) FROM dbo.Fact_Detalle_Venta;

-- 2. Conciliacion de los totales de ventas (DW)
SELECT
    COUNT(*) AS TotalDetalles,
    COUNT(DISTINCT DetalleVentaID) AS DetallesUnicos,
    COUNT(DISTINCT VentaID) AS VentasDistintas,
    SUM(CAST(Cantidad AS BIGINT)) AS UnidadesVendidas,
    SUM(CAST(MontoTotal AS DECIMAL(29,4))) AS ImporteTotal,
    SUM(CASE WHEN EmpleadoID = -1 THEN 1 ELSE 0 END) AS DetallesSinVendedor
FROM dbo.Fact_Detalle_Venta;

-- 3. Totales originales para comparar (BikeZ)
SELECT
    COUNT(*) AS TotalDetalles,
    COUNT(DISTINCT D.DetalleVentaID) AS DetallesUnicos,
    COUNT(DISTINCT D.VentaID) AS VentasDistintas,
    SUM(CAST(D.Cantidad AS BIGINT)) AS UnidadesVendidas,
    SUM(CAST(CAST(D.Cantidad AS DECIMAL(9,0)) * CAST(D.PrecioUnitario AS DECIMAL(19,4)) AS DECIMAL(29,4))) AS ImporteTotal,
    SUM(CASE WHEN V.VendedorID IS NULL THEN 1 ELSE 0 END) AS DetallesSinVendedor
FROM BikeZ.dbo.DetalleVentas AS D
JOIN BikeZ.dbo.Ventas AS V ON D.VentaID = V.VentaID;

-- 4. Registro tecnico y duplicados en la tabla de hechos
SELECT EmpleadoID, Cargo
FROM dbo.Dim_Empleado
WHERE EmpleadoID = -1;

SELECT DetalleVentaID, COUNT(*) AS Repeticiones
FROM dbo.Fact_Detalle_Venta
GROUP BY DetalleVentaID
HAVING COUNT(*) > 1;

-- 5. Validacion de integridad: origen + dimensiones + fechas
-- Resultado esperado: TotalDetalles = cantidad de filas en Fact y DetallesConDiferencias = 0.
SELECT
    COUNT(*) AS TotalDetalles,
    SUM(CASE WHEN D.DetalleVentaID IS NULL THEN 1 ELSE 0 END) AS DetallesSinOrigen,
    SUM(CASE WHEN
        D.DetalleVentaID IS NULL
        OR V.VentaID IS NULL
        OR C.ClienteID IS NULL
        OR P.ProductoID IS NULL
        OR E.EmpleadoID IS NULL
        OR T.TerritorioID IS NULL
        OR TV.FechaID IS NULL
        OR (F.Cantidad <= 0)
        OR (F.PrecioUnitario < 0)
        OR (F.MontoTotal < 0)
        OR ABS(CAST(F.MontoTotal AS DECIMAL(29,4)) - CAST(CAST(F.Cantidad AS DECIMAL(9,0)) * F.PrecioUnitario AS DECIMAL(29,4))) > 0.0001
        THEN 1 ELSE 0 END) AS DetallesConDiferencias
FROM dbo.Fact_Detalle_Venta AS F
LEFT JOIN BikeZ.dbo.DetalleVentas AS D ON F.DetalleVentaID = D.DetalleVentaID
LEFT JOIN BikeZ.dbo.Ventas AS V ON D.VentaID = V.VentaID
LEFT JOIN dbo.Dim_Cliente AS C ON F.ClienteID = C.ClienteID
LEFT JOIN dbo.Dim_Producto AS P ON F.ProductoID = P.ProductoID
LEFT JOIN dbo.Dim_Empleado AS E ON F.EmpleadoID = E.EmpleadoID
LEFT JOIN dbo.Dim_Territorio AS T ON F.TerritorioID = T.TerritorioID
LEFT JOIN dbo.Dim_Tiempo AS TV ON F.FechaVentaID = TV.FechaID;

-- 6. Verificar origen no omitido del destino
SELECT COUNT(*) AS DetallesDelOrigenAusentesEnDW
FROM BikeZ.dbo.DetalleVentas AS D
LEFT JOIN dbo.Fact_Detalle_Venta AS F
    ON D.DetalleVentaID = F.DetalleVentaID
WHERE F.DetalleVentaID IS NULL;

-- 7. KPI 1: ingresos por ventas
SELECT SUM(MontoTotal) AS IngresosPorVentas
FROM dbo.Fact_Detalle_Venta;

-- 8. KPI 2: unidades vendidas
SELECT SUM(CAST(Cantidad AS BIGINT)) AS UnidadesVendidas
FROM dbo.Fact_Detalle_Venta;

-- 9. KPI 3: ticket promedio (por venta, no por detalle)
SELECT
    SUM(MontoTotal) / NULLIF(COUNT(DISTINCT VentaID), 0) AS TicketPromedio
FROM dbo.Fact_Detalle_Venta;

-- 10. KPI 4: porcentaje de clientes recurrentes
WITH ComprasPorCliente AS (
    SELECT ClienteID, COUNT(DISTINCT VentaID) AS NumeroVentas
    FROM dbo.Fact_Detalle_Venta
    GROUP BY ClienteID
)
SELECT
    COUNT(*) AS ClientesCompradores,
    SUM(CASE WHEN NumeroVentas >= 2 THEN 1 ELSE 0 END) AS ClientesRecurrentes,
    CAST(100.0 * SUM(CASE WHEN NumeroVentas >= 2 THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0) AS DECIMAL(10,2)) AS PorcentajeRecurrentes
FROM ComprasPorCliente;

-- 11. KPI 5: dias promedio desde venta hasta envio
-- Como la Dim_Tiempo solo tiene fecha de venta, calculamos este indicador a partir de la base origen.
SELECT
    AVG(CAST(DATEDIFF(DAY, V.Fecha, V.FechaEnvio) AS DECIMAL(18,4))) AS DiasPromedioHastaEnvio
FROM BikeZ.dbo.Ventas AS V
WHERE V.FechaEnvio IS NOT NULL;

-- 12. Analisis complementario: ingresos y cantidad de almacenes por territorio
-- No representa ventas generadas individualmente por cada almacen.
SELECT
    T.Nombre_Territorio,
    T.Pais,
    T.Grupo,
    T.CantidadAlmacenes,
    COUNT(DISTINCT F.VentaID) AS Ventas,
    COALESCE(SUM(F.MontoTotal), 0) AS IngresosPorVentas
FROM dbo.Dim_Territorio AS T
LEFT JOIN dbo.Fact_Detalle_Venta AS F
    ON T.TerritorioID = F.TerritorioID
GROUP BY T.Nombre_Territorio, T.Pais, T.Grupo, T.CantidadAlmacenes
ORDER BY IngresosPorVentas DESC;

-- 13. Verificacion final de existencia de tablas esperadas
SELECT
    OBJECT_ID(N'dbo.Dim_Tiempo') AS Dim_Tiempo_Existe,
    OBJECT_ID(N'dbo.Dim_Cliente') AS Dim_Cliente_Existe,
    OBJECT_ID(N'dbo.Dim_Producto') AS Dim_Producto_Existe,
    OBJECT_ID(N'dbo.Dim_Empleado') AS Dim_Empleado_Existe,
    OBJECT_ID(N'dbo.Dim_Territorio') AS Dim_Territorio_Existe,
    OBJECT_ID(N'dbo.Fact_Detalle_Venta') AS Fact_Detalle_Venta_Existe;
GO

