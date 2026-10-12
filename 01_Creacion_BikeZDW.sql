/* =====================================================================
   BIKEZ - CERTAMEN 2 INTELIGENCIA DE NEGOCIOS
   FASE 1 / SCRIPT 01: CREACION DEL MODELO DIMENSIONAL (ESQUEMA ESTRELLA)

   Origen:       BikeZ (solo lectura durante el ETL posterior)
   Destino:      BikeZDW
   Estructura:   5 dimensiones + 1 tabla de hechos
   Granularidad: 1 fila por DetalleVentaID (linea de venta)

   IMPORTANTE:
   - NO borra ni modifica tablas ni datos de BikeZ.
   - NO borra datos ni tablas de una BikeZDW ya existente.
   - Crea dimensiones y hechos VACIOS, excepto Empleado desconocido (-1).
   - Los datos reales se cargaran luego mediante Visual Studio / SSIS.
   - El script puede volver a ejecutarse: omite objetos ya creados.
   ===================================================================== */

USE [master];
GO

IF DB_ID(N'BikeZDW') IS NULL
BEGIN
    CREATE DATABASE [BikeZDW];
    PRINT N'Base BikeZDW creada.';
END
ELSE
    PRINT N'La base BikeZDW ya existia; no se ha borrado ni reiniciado.';
GO

USE [BikeZDW];
GO

/* ---------------------------------------------------------------------
   DIM 1 - TIEMPO
   FechaKey = AAAAMMDD (ej.: 20150701), no IDENTITY.
   Misma dimension, dos roles en el hecho: venta y envio.
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.Dim_Tiempo', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Dim_Tiempo
    (
        FechaKey        INT           NOT NULL,
        Fecha           DATE          NOT NULL,
        Dia             TINYINT       NOT NULL,
        Mes             TINYINT       NOT NULL,
        Trimestre       TINYINT       NOT NULL,
        Anio            SMALLINT      NOT NULL,
        DiaSemana       NVARCHAR(20)  NOT NULL,
        EsFinDeSemana   BIT           NOT NULL,
        CONSTRAINT PK_Dim_Tiempo PRIMARY KEY (FechaKey),
        CONSTRAINT UQ_Dim_Tiempo_Fecha UNIQUE (Fecha),
        CONSTRAINT CK_Dim_Tiempo_Mes CHECK (Mes BETWEEN 1 AND 12),
        CONSTRAINT CK_Dim_Tiempo_Trimestre CHECK (Trimestre BETWEEN 1 AND 4),
        CONSTRAINT CK_Dim_Tiempo_Dia CHECK (Dia BETWEEN 1 AND 31),
        CONSTRAINT CK_Dim_Tiempo_FechaKey CHECK
            (FechaKey = CONVERT(INT, CONVERT(CHAR(8), Fecha, 112)))
    );
    PRINT N'Creada: Dim_Tiempo';
END;
GO

/* ---------------------------------------------------------------------
   DIM 2 - CLIENTE
   ClienteKey = clave sustituta generada por SQL Server.
   ClienteID = identificador original de negocio (no PK en el DW).
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.Dim_Cliente', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Dim_Cliente
    (
        ClienteKey      INT           IDENTITY(1,1) NOT NULL,
        ClienteID       INT           NOT NULL,
        Nombre          NVARCHAR(50)  NULL,
        Apellido        NVARCHAR(50)  NULL,
        CONSTRAINT PK_Dim_Cliente PRIMARY KEY (ClienteKey),
        CONSTRAINT UQ_Dim_Cliente_ClienteID UNIQUE (ClienteID)
    );
    PRINT N'Creada: Dim_Cliente';
END;
GO

/* ---------------------------------------------------------------------
   DIM 3 - PRODUCTO
   Categoria se integra en la misma dimension (esquema estrella).
   Para CategoriaID NULL, el ETL usara Categoria = 'Sin categoria'.
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.Dim_Producto', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Dim_Producto
    (
        ProductoKey     INT           IDENTITY(1,1) NOT NULL,
        ProductoID      INT           NOT NULL,
        Producto        NVARCHAR(50)  NOT NULL,
        Color           NVARCHAR(15)  NULL,
        Categoria       NVARCHAR(50)  NOT NULL,
        CONSTRAINT PK_Dim_Producto PRIMARY KEY (ProductoKey),
        CONSTRAINT UQ_Dim_Producto_ProductoID UNIQUE (ProductoID)
    );
    PRINT N'Creada: Dim_Producto';
END;
GO

/* ---------------------------------------------------------------------
   DIM 4 - EMPLEADO
   EmpleadoKey = clave sustituta. -1 se reserva para 'Sin asignar'.
   EmpleadoID NULL SOLO en el registro tecnico; los ID reales son unicos.
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.Dim_Empleado', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Dim_Empleado
    (
        EmpleadoKey       INT           IDENTITY(1,1) NOT NULL,
        EmpleadoID        INT           NULL,
        Cargo             NVARCHAR(50)  NULL,
        Genero            NCHAR(1)      NULL,
        FechaNacimiento   DATE          NULL,
        FechaContratacion DATE          NULL,
        CONSTRAINT PK_Dim_Empleado PRIMARY KEY (EmpleadoKey)
    );
    PRINT N'Creada: Dim_Empleado';
END;
GO

IF OBJECT_ID(N'dbo.Dim_Empleado', N'U') IS NOT NULL
   AND NOT EXISTS
       (SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.Dim_Empleado')
          AND name = N'UX_Dim_Empleado_EmpleadoID')
BEGIN
    CREATE UNIQUE INDEX UX_Dim_Empleado_EmpleadoID
        ON dbo.Dim_Empleado (EmpleadoID)
        WHERE EmpleadoID IS NOT NULL;
    PRINT N'Creado indice unico de EmpleadoID (ignorando NULL).';
END;
GO

/* Registro tecnico necesario para no perder ventas con VendedorID NULL. */
IF NOT EXISTS (SELECT 1 FROM dbo.Dim_Empleado WHERE EmpleadoKey = -1)
BEGIN
    SET IDENTITY_INSERT dbo.Dim_Empleado ON;
    INSERT INTO dbo.Dim_Empleado
        (EmpleadoKey, EmpleadoID, Cargo, Genero, FechaNacimiento, FechaContratacion)
    VALUES
        (-1, NULL, N'Sin asignar', NULL, NULL, NULL);
    SET IDENTITY_INSERT dbo.Dim_Empleado OFF;
    PRINT N'Insertado empleado tecnico EmpleadoKey = -1.';
END;
GO

/* ---------------------------------------------------------------------
   DIM 5 - TERRITORIO
   CantidadAlmacenes es el conteo por territorio en la fuente al cargar.
   No representa ventas de almacenes ni un historico de su cantidad.
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.Dim_Territorio', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Dim_Territorio
    (
        TerritorioKey     INT           IDENTITY(1,1) NOT NULL,
        TerritorioID      INT           NOT NULL,
        Territorio        NVARCHAR(50)  NOT NULL,
        Pais              NVARCHAR(50)  NOT NULL,
        Grupo             NVARCHAR(50)  NOT NULL,
        CantidadAlmacenes INT           NOT NULL,
        CONSTRAINT PK_Dim_Territorio PRIMARY KEY (TerritorioKey),
        CONSTRAINT UQ_Dim_Territorio_TerritorioID UNIQUE (TerritorioID),
        CONSTRAINT CK_Dim_Territorio_Almacenes CHECK (CantidadAlmacenes >= 0)
    );
    PRINT N'Creada: Dim_Territorio';
END;
GO

/* ---------------------------------------------------------------------
   HECHOS - DETALLE DE VENTA
   DetalleVentaID es PK original, porque ya se verifico su unicidad.
   VentaID es identificador degenerado, necesario para COUNT(DISTINCT).
   MontoTotal DECIMAL(29,4): permite producto entero x precio monetario.
   FechaEnvioKey admite NULL para futuros registros sin envio.
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.Fact_Detalle_Venta', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Fact_Detalle_Venta
    (
        DetalleVentaID   INT           NOT NULL,
        VentaID          INT           NOT NULL,
        FechaVentaKey    INT           NOT NULL,
        FechaEnvioKey    INT           NULL,
        ClienteKey       INT           NOT NULL,
        ProductoKey      INT           NOT NULL,
        EmpleadoKey      INT           NOT NULL,
        TerritorioKey    INT           NOT NULL,
        Cantidad         SMALLINT      NOT NULL,
        PrecioUnitario   DECIMAL(19,4) NOT NULL,
        MontoTotal       DECIMAL(29,4) NOT NULL,

        CONSTRAINT PK_Fact_Detalle_Venta PRIMARY KEY (DetalleVentaID),

        CONSTRAINT FK_Fact_FechaVenta
            FOREIGN KEY (FechaVentaKey) REFERENCES dbo.Dim_Tiempo(FechaKey),
        CONSTRAINT FK_Fact_FechaEnvio
            FOREIGN KEY (FechaEnvioKey) REFERENCES dbo.Dim_Tiempo(FechaKey),
        CONSTRAINT FK_Fact_Cliente
            FOREIGN KEY (ClienteKey) REFERENCES dbo.Dim_Cliente(ClienteKey),
        CONSTRAINT FK_Fact_Producto
            FOREIGN KEY (ProductoKey) REFERENCES dbo.Dim_Producto(ProductoKey),
        CONSTRAINT FK_Fact_Empleado
            FOREIGN KEY (EmpleadoKey) REFERENCES dbo.Dim_Empleado(EmpleadoKey),
        CONSTRAINT FK_Fact_Territorio
            FOREIGN KEY (TerritorioKey) REFERENCES dbo.Dim_Territorio(TerritorioKey),

        CONSTRAINT CK_Fact_Cantidad CHECK (Cantidad > 0),
        CONSTRAINT CK_Fact_PrecioUnitario CHECK (PrecioUnitario >= 0),
        CONSTRAINT CK_Fact_MontoTotal CHECK (MontoTotal >= 0),
        CONSTRAINT CK_Fact_MontoCalculado CHECK
            (MontoTotal = CAST(Cantidad AS DECIMAL(9,0)) * PrecioUnitario)
    );
    PRINT N'Creada: Fact_Detalle_Venta';
END;
GO

/* Indices para busqueda de transacciones y filtros analiticos comunes. */
IF OBJECT_ID(N'dbo.Fact_Detalle_Venta', N'U') IS NOT NULL
   AND NOT EXISTS
       (SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.Fact_Detalle_Venta')
          AND name = N'IX_Fact_VentaID')
    CREATE INDEX IX_Fact_VentaID ON dbo.Fact_Detalle_Venta(VentaID);
GO

IF OBJECT_ID(N'dbo.Fact_Detalle_Venta', N'U') IS NOT NULL
   AND NOT EXISTS
       (SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.Fact_Detalle_Venta')
          AND name = N'IX_Fact_FechaVentaKey')
    CREATE INDEX IX_Fact_FechaVentaKey ON dbo.Fact_Detalle_Venta(FechaVentaKey);
GO

/* ---------------------------------------------------------------------
   VERIFICACION (despues de ejecutar):
   - deben existir 6 tablas de usuario en BikeZDW
   - deben existir 6 relaciones FK desde Fact_Detalle_Venta
   - Dim_Empleado debe contener 1 registro tecnico, EmpleadoKey = -1
   - las otras tablas estaran vacias hasta ejecutar el ETL
   --------------------------------------------------------------------- */
PRINT N'========== TABLAS DE BikeZDW ==========';
SELECT name AS Tabla
FROM sys.tables
WHERE name IN
    (N'Dim_Tiempo', N'Dim_Cliente', N'Dim_Producto',
     N'Dim_Empleado', N'Dim_Territorio', N'Fact_Detalle_Venta')
ORDER BY name;

PRINT N'========== RELACIONES DE LA TABLA DE HECHOS ==========';
SELECT
    fk.name AS ClaveForanea,
    OBJECT_NAME(fk.parent_object_id) AS TablaOrigen,
    OBJECT_NAME(fk.referenced_object_id) AS TablaDestino
FROM sys.foreign_keys fk
WHERE fk.parent_object_id = OBJECT_ID(N'dbo.Fact_Detalle_Venta')
ORDER BY fk.name;

PRINT N'========== REGISTRO TECNICO ==========';
SELECT EmpleadoKey, EmpleadoID, Cargo
FROM dbo.Dim_Empleado
WHERE EmpleadoKey = -1;
GO
