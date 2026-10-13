/*
    BIKEZ - VALIDACION DEL DATA WAREHOUSE (FASE 1)
    Ejecutar en SQL Server Management Studio.
    NO MODIFICA DATOS: solo sentencias SELECT.
    Para comparaciones contra el origen, deben existir BikeZ y BikeZDW.
*/
USE BikeZDW;
GO

-- 1. Cantidad de registros por tabla
SELECT 'Dim_Tiempo' AS Tabla, COUNT(*) AS Registros FROM dbo.Dim_Tiempo
UNION ALL SELECT 'Dim_Cliente', COUNT(*) FROM dbo.Dim_Cliente
UNION ALL SELECT 'Dim_Producto', COUNT(*) FROM dbo.Dim_Producto
UNION ALL SELECT 'Dim_Empleado', COUNT(*) FROM dbo.Dim_Empleado
UNION ALL SELECT 'Dim_Territorio', COUNT(*) FROM dbo.Dim_Territorio
UNION ALL SELECT 'Fact_Detalle_Venta', COUNT(*) FROM dbo.Fact_Detalle_Venta;

-- 2. Conciliacion de los totales de ventas (DW)
SELECT
    COUNT(*) AS TotalDetalles,
    COUNT(DISTINCT DetalleVentaID) AS DetallesUnicos,
    COUNT(DISTINCT VentaID) AS VentasDistintas,
    SUM(CAST(Cantidad AS BIGINT)) AS UnidadesVendidas,
    SUM(MontoTotal) AS ImporteTotal,
    SUM(CASE WHEN EmpleadoKey = -1 THEN 1 ELSE 0 END) AS DetallesSinVendedor
FROM dbo.Fact_Detalle_Venta;

-- 3. Totales originales para comparar (BikeZ)
SELECT
    COUNT(*) AS TotalDetalles,
    COUNT(DISTINCT D.DetalleVentaID) AS DetallesUnicos,
    COUNT(DISTINCT D.VentaID) AS VentasDistintas,
    SUM(CAST(D.Cantidad AS BIGINT)) AS UnidadesVendidas,
    SUM(CAST(CAST(D.Cantidad AS DECIMAL(9,0))
         * CAST(D.PrecioUnitario AS DECIMAL(19,4)) AS DECIMAL(29,4))) AS ImporteTotal,
    SUM(CASE WHEN V.VendedorID IS NULL THEN 1 ELSE 0 END) AS DetallesSinVendedor
FROM BikeZ.dbo.DetalleVentas AS D
JOIN BikeZ.dbo.Ventas AS V ON D.VentaID = V.VentaID;

-- 4. Registro tecnico y duplicados en la tabla de hechos
SELECT EmpleadoKey, EmpleadoID, Cargo
FROM dbo.Dim_Empleado
WHERE EmpleadoKey = -1;

SELECT DetalleVentaID, COUNT(*) AS Repeticiones
FROM dbo.Fact_Detalle_Venta
GROUP BY DetalleVentaID
HAVING COUNT(*) > 1;

-- 5. Diferencias por linea de detalle (comparacion nulo-segura)
-- Resultado esperado: TotalDetalles = 121317 y DetallesConDiferencias = 0.
SELECT
    COUNT(*) AS TotalDetalles,
    SUM(CASE WHEN D.DetalleVentaID IS NULL THEN 1 ELSE 0 END) AS DetallesSinOrigen,
    SUM(CASE WHEN
        D.DetalleVentaID IS NULL OR V.VentaID IS NULL
        OR C.ClienteKey IS NULL OR P.ProductoKey IS NULL
        OR E.EmpleadoKey IS NULL OR T.TerritorioKey IS NULL
        OR TV.FechaKey IS NULL
        OR (V.FechaEnvio IS NOT NULL AND TE.FechaKey IS NULL)
        OR EXISTS (
            SELECT
                F.VentaID, F.Cantidad, F.PrecioUnitario, F.MontoTotal,
                F.FechaVentaKey, F.FechaEnvioKey,
                C.ClienteID, P.ProductoID, T.TerritorioID,
                CASE WHEN F.EmpleadoKey = -1 THEN NULL ELSE E.EmpleadoID END
            EXCEPT
            SELECT
                D.VentaID, D.Cantidad,
                CAST(D.PrecioUnitario AS DECIMAL(19,4)),
                CAST(CAST(D.Cantidad AS DECIMAL(9,0))
                     * CAST(D.PrecioUnitario AS DECIMAL(19,4)) AS DECIMAL(29,4)),
                CONVERT(INT, CONVERT(CHAR(8), V.Fecha, 112)),
                CASE WHEN V.FechaEnvio IS NULL THEN NULL
                     ELSE CONVERT(INT, CONVERT(CHAR(8), V.FechaEnvio, 112)) END,
                V.ClienteID, D.ProductoID, V.TerritorioID, V.VendedorID
        )
        THEN 1 ELSE 0 END) AS DetallesConDiferencias
FROM dbo.Fact_Detalle_Venta AS F
LEFT JOIN BikeZ.dbo.DetalleVentas AS D ON F.DetalleVentaID = D.DetalleVentaID
LEFT JOIN BikeZ.dbo.Ventas AS V ON D.VentaID = V.VentaID
LEFT JOIN dbo.Dim_Cliente AS C ON F.ClienteKey = C.ClienteKey
LEFT JOIN dbo.Dim_Producto AS P ON F.ProductoKey = P.ProductoKey
LEFT JOIN dbo.Dim_Empleado AS E ON F.EmpleadoKey = E.EmpleadoKey
LEFT JOIN dbo.Dim_Territorio AS T ON F.TerritorioKey = T.TerritorioKey
LEFT JOIN dbo.Dim_Tiempo AS TV ON F.FechaVentaKey = TV.FechaKey
LEFT JOIN dbo.Dim_Tiempo AS TE ON F.FechaEnvioKey = TE.FechaKey;

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
-- Denominador: clientes que registran al menos una venta.
WITH ComprasPorCliente AS (
    SELECT ClienteKey, COUNT(DISTINCT VentaID) AS NumeroVentas
    FROM dbo.Fact_Detalle_Venta
    GROUP BY ClienteKey
)
SELECT
    COUNT(*) AS ClientesCompradores,
    SUM(CASE WHEN NumeroVentas >= 2 THEN 1 ELSE 0 END) AS ClientesRecurrentes,
    CAST(100.0 * SUM(CASE WHEN NumeroVentas >= 2 THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0) AS DECIMAL(10,2)) AS PorcentajeRecurrentes
FROM ComprasPorCliente;

-- 11. KPI 5: dias promedio desde venta hasta envio (1 registro por VentaID)
WITH FechasPorVenta AS (
    SELECT
        F.VentaID,
        MIN(TV.Fecha) AS FechaVenta,
        MIN(TE.Fecha) AS FechaEnvio
    FROM dbo.Fact_Detalle_Venta AS F
    INNER JOIN dbo.Dim_Tiempo AS TV ON F.FechaVentaKey = TV.FechaKey
    LEFT JOIN dbo.Dim_Tiempo AS TE ON F.FechaEnvioKey = TE.FechaKey
    GROUP BY F.VentaID
)
SELECT
    COUNT(*) AS VentasConFechaEnvio,
    AVG(CAST(DATEDIFF(DAY, FechaVenta, FechaEnvio) AS DECIMAL(18,4)))
        AS DiasPromedioHastaEnvio
FROM FechasPorVenta
WHERE FechaEnvio IS NOT NULL;

-- 12. Analisis complementario: ingresos y cantidad de almacenes por territorio
-- No representa ventas generadas individualmente por cada almacen.
SELECT
    T.Territorio, T.Pais, T.Grupo, T.CantidadAlmacenes,
    COUNT(DISTINCT F.VentaID) AS Ventas,
    COALESCE(SUM(F.MontoTotal), 0) AS IngresosPorVentas
FROM dbo.Dim_Territorio AS T
LEFT JOIN dbo.Fact_Detalle_Venta AS F
    ON T.TerritorioKey = F.TerritorioKey
GROUP BY T.Territorio, T.Pais, T.Grupo, T.CantidadAlmacenes
ORDER BY IngresosPorVentas DESC;
