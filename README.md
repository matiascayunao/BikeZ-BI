# BikeZ - Inteligencia de Negocios

## Integrantes y paralelo

- Martín Arriagada
- Matías Cayunao
- Tomás Saavedra
- Simón Vargas

**Paralelo:** 300

## 1. Sobre el caso

BikeZ es una empresa que vende artículos para motocross y que ha crecido bastante. Con ese crecimiento, también ha aumentado la información que maneja sobre ventas, productos, clientes y territorios.

La idea de este trabajo es aprovechar esos datos para entender mejor cómo están funcionando las ventas y contar con información que ayude a tomar decisiones. Para eso usamos la base transaccional `BikeZ`, creamos una base dimensional llamada `BikeZDW` en SQL Server y desarrollamos un proceso ETL en Visual Studio con SSIS.

En esta primera fase nos enfocamos en el modelo dimensional, la carga de información y la comprobación de que los datos se hayan traspasado correctamente. Los cubos OLAP y Power BI corresponden a la segunda fase.

## 2. Qué queremos analizar

Principalmente buscamos conocer cuánto vende BikeZ, qué productos tienen más movimiento, cómo se comportan los clientes, cuánto tiempo transcurre hasta el envío y cómo se distribuyen las ventas entre los distintos territorios.

A partir de eso definimos cinco indicadores (KPI):

| KPI | Cómo se calcula | Qué nos permite responder |
| --- | --- | --- |
| **Ingresos por ventas** | Suma de `MontoTotal`. | ¿Cuánto se vende por período, producto, categoría o territorio? |
| **Unidades vendidas** | Suma de `Cantidad`. | ¿Qué productos se venden más? |
| **Ticket promedio** | Ingresos totales / número de ventas distintas (`VentaID`). | ¿Cuánto se vende en promedio por compra? |
| **Clientes recurrentes** | Clientes con dos o más ventas distintas / clientes que han comprado × 100. | ¿Qué porcentaje de compradores vuelve a comprar? |
| **Tiempo promedio hasta el envío** | Promedio de días entre la venta y su fecha de envío, considerando cada `VentaID` una sola vez. | ¿Cuántos días pasan, en promedio, antes de enviar un pedido? |

Es importante distinguir que los ingresos no son ganancias, porque no tenemos información de costos. Además, podemos calcular el tiempo hasta el envío, pero no hasta la entrega final al cliente.

También nos interesa comparar las ventas de cada territorio con la cantidad de almacenes que tiene. Esto puede ayudar a revisar la cobertura, aunque no podemos saber cuánto vendió cada almacén, porque la base no relaciona directamente las ventas con un almacén específico.

## 3. Modelo dimensional: cuatro pasos de Kimball

### Paso 1. Proceso de negocio

Escogimos la **venta de productos de motocross**, ya que es el proceso que nos permite responder las principales preguntas comerciales de BikeZ.

### Paso 2. Granularidad

Cada fila de `Fact_Detalle_Venta` representa **una línea de detalle de un producto vendido dentro de una venta**.

Elegimos este nivel porque una venta puede incluir varios productos. Así podemos analizar cada producto, su cantidad y su precio sin perder la relación con la venta completa. En nuestros datos, `DetalleVentaID` identifica cada detalle y `VentaID` permite agrupar los detalles que pertenecen a una misma compra.

### Paso 3. Dimensiones

Usamos cinco dimensiones:

| Dimensión | Información que contiene |
| --- | --- |
| `Dim_Tiempo` | Fecha, día, mes, trimestre, año, día de la semana y si es fin de semana. |
| `Dim_Cliente` | ID original del cliente, nombre y apellido. |
| `Dim_Producto` | ID original del producto, nombre, color y categoría. |
| `Dim_Empleado` | ID original del empleado, cargo, género, fecha de nacimiento y contratación. |
| `Dim_Territorio` | ID original del territorio, nombre, país, grupo y cantidad de almacenes. |

Las dimensiones usan claves propias (`ClienteKey`, `ProductoKey`, `EmpleadoKey` y `TerritorioKey`), mientras que los ID originales se mantienen para identificar los registros de la base transaccional. En `Dim_Tiempo`, `FechaKey` utiliza el formato `AAAAMMDD`.

La dimensión de tiempo se relaciona dos veces con la tabla de hechos: una para la **fecha de venta** y otra para la **fecha de envío**. Así no es necesario crear dos tablas de fechas diferentes.

<img width="779" height="603" alt="Modelo_Estrella_BikeZDW" src="https://github.com/user-attachments/assets/0bb40b42-32d0-4d05-8b5b-48c2ad7fc9f2" />


### Paso 4. Tabla de hechos y medidas

La tabla central es `Fact_Detalle_Venta`. Contiene `DetalleVentaID` como clave primaria, `VentaID` para identificar la venta y las claves que la relacionan con las cinco dimensiones (dos de ellas con `Dim_Tiempo`).

Sus medidas son:

- `Cantidad`: unidades vendidas en cada detalle.
- `PrecioUnitario`: precio registrado para ese producto.
- `MontoTotal`: resultado de multiplicar `Cantidad` por `PrecioUnitario`.

Para calcular ingresos usamos `MontoTotal`; sumar los precios unitarios no daría el total vendido.

Escogimos un **modelo estrella** porque la tabla de hechos se conecta directamente con las dimensiones. Por ejemplo, la categoría queda dentro de `Dim_Producto` y el país dentro de `Dim_Territorio`, sin agregar tablas adicionales para consultarlos.

## 4. Datos que tuvimos que revisar

La base original incluye `Ventas`, `DetalleVentas`, `Clientes`, `Productos`, `Categorias`, `Empleados`, `Territorios`, `Paises` y `Almacenes`.

Al revisar los registros encontramos algunos datos incompletos. Tomamos estas decisiones para mantener la información de ventas:

- **Ventas sin vendedor identificado:** agregamos en `Dim_Empleado` un registro llamado «Sin asignar» con `EmpleadoKey = -1`. Así esos detalles siguen apareciendo en los resultados.
- **Productos sin categoría:** usamos `LEFT JOIN` y `COALESCE` para mostrar «Sin categoría» cuando corresponde.
- **Clientes sin nombre o apellido y productos sin color:** conservamos los valores `NULL`, en lugar de inventar información.
- **Territorio:** para analizar una venta usamos `Ventas.TerritorioID`, no el territorio del empleado.
- **Almacenes:** contamos los almacenes asociados a cada territorio y guardamos ese dato en `Dim_Territorio`. Es una referencia de la situación registrada en la base, no la cantidad histórica de almacenes al momento de cada venta.

También construimos un calendario con todos los días del período, incluidos los que no tuvieron ventas. En esta fase no implementamos un historial de cambios de las dimensiones (SCD tipo 2).

## 5. Cómo hicimos el ETL

Trabajamos con **SQL Server 2019, SSMS y Visual Studio 2022 con SSIS**. El proyecto está en `BikeZ_ETL/BikeZ_ETL.sln`, y el paquete que ejecutamos es `Carga_BikeZ.dtsx`.

El flujo de control se ejecuta en este orden:

```text
Borrar Datos Destino
        |
    Dim_Tiempo
        |
    Dim_Cliente
        |
    Dim_Producto
        |
    Dim_Empleado
        |
    Dim_Territorio
        |
Fact_Detalle_Venta
```

Primero limpiamos los datos previamente cargados en `BikeZDW`, manteniendo el empleado técnico «Sin asignar». Después cargamos las dimensiones y, al final, la tabla de hechos. Ese orden es importante porque la tabla de hechos necesita las claves de las dimensiones.

Utilizamos orígenes y destinos OLE DB. Varias transformaciones se hicieron directamente en las consultas SQL de los orígenes, por ejemplo las uniones de tablas, el tratamiento de nulos, los cálculos y la obtención de las claves del modelo dimensional.

## 6. Comprobación de resultados

Ejecutamos el paquete SSIS y comprobamos la carga en SQL Server. También lo ejecutamos una segunda vez para verificar que no se duplicaran los registros.

Las tablas de `BikeZDW` quedaron con estos datos:

| Tabla | Registros |
| --- | ---: |
| `Dim_Tiempo` | 1.134 |
| `Dim_Cliente` | 19.820 |
| `Dim_Producto` | 504 |
| `Dim_Empleado` | 291 (290 empleados y un registro técnico) |
| `Dim_Territorio` | 10 |
| `Fact_Detalle_Venta` | 121.317 |

Además, comparamos los resultados de la tabla de hechos con la base original:

| Comprobación | Resultado |
| --- | ---: |
| Detalles de venta | 121.317 |
| Detalles únicos | 121.317 |
| Ventas distintas | 31.465 |
| Unidades vendidas | 274.914 |
| Importe total | 110.373.889,3134 |
| Detalles sin vendedor identificado | 60.397 |
| Detalles que no encuentran su registro de origen | 0 |
| Detalles con diferencias en la comparación | 0 |

El importe corresponde a los valores registrados en la base, sin asumir una moneda que no está indicada. Las consultas de comprobación están en `02_Validacion_BikeZDW.sql`, un archivo adicional que dejamos para repetir las pruebas cuando sea necesario.

## 7. Archivos del repositorio

```text
BikeZ-BI/
├── .gitignore
├── 01_Creacion_BikeZDW.sql
├── 02_Validacion_BikeZDW.sql
├── Modelo_Estrella_BikeZDW.png
├── BikeZ.bak
├── BikeZDW.bak
├── BikeZ_ETL/
│   ├── BikeZ_ETL.sln
│   ├── BikeZ_ETL.dtproj
│   ├── Carga_BikeZ.dtsx
│   └── Project.params
└── README.md
```

`BikeZ.bak` es el respaldo de la base transaccional y `BikeZDW.bak` corresponde a nuestra base dimensional con los datos cargados. El archivo `01_Creacion_BikeZDW.sql` permite crear las tablas y sus relaciones.

## 8. Cómo revisar o ejecutar el trabajo

Si solo se quiere revisar el resultado, se puede restaurar `BikeZDW.bak` en SQL Server y consultar las tablas desde SSMS.

Para repetir el proceso completo:

1. Restaurar `BikeZ.bak` con el nombre `BikeZ`.
2. Ejecutar `01_Creacion_BikeZDW.sql` para crear la base `BikeZDW` y sus tablas.
3. Abrir `BikeZ_ETL/BikeZ_ETL.sln` en Visual Studio con la extensión de SSIS.
4. Revisar las conexiones OLE DB: `BikeZ` como origen y `BikeZDW` como destino. Puede ser necesario cambiar el servidor o la autenticación si se usa otro computador.
5. Ejecutar `Carga_BikeZ.dtsx`.
6. Ejecutar las consultas de `02_Validacion_BikeZDW.sql` y comparar los resultados.

Hay que tener en cuenta que el paquete **borra los datos previamente cargados en `BikeZDW` antes de volver a cargarlos**. Por eso no se debe ejecutar sobre una base de destino cuyos datos se quieran conservar sin respaldo.
