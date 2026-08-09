CREATE PROCEDURE pr_AjusteInventarioOptimizado_v2
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRAN;

        ---------------------------------------------------------
        -- 1) Preparar tabla temporal con los cálculos por referencia
        ---------------------------------------------------------
        IF OBJECT_ID('tempdb..#Calculos') IS NOT NULL
            DROP TABLE #Calculos;

        CREATE TABLE #Calculos
        (
            CODIGO           VARCHAR(100),
            CANTIDAD         DECIMAL(18,6),
            TIPO             CHAR(1),
            IDREFERENCIA     INT,
            IDSTOCK_ACTIVO   INT,
            SALDO_ACTUAL     DECIMAL(18,6),
            VALOR_UNITARIO   DECIMAL(18,6),
            NUEVO_SALDO      DECIMAL(18,6),
            VALOR_TOTAL      DECIMAL(18,6),
            VALOR_TOTAL_SALDO DECIMAL(18,6)
        );

        INSERT INTO #Calculos (CODIGO, CANTIDAD, TIPO, IDREFERENCIA, IDSTOCK_ACTIVO, SALDO_ACTUAL, VALOR_UNITARIO, NUEVO_SALDO, VALOR_TOTAL, VALOR_TOTAL_SALDO)
        SELECT
            R.CODIGO,
            CONVERT(DECIMAL(18,6), R.CANTIDAD) AS CANTIDAD,
            R.TIPO,
            RF.IDREFERENCIA,
            S.IDMM_RF_STOCK AS IDSTOCK_ACTIVO,
            CONVERT(DECIMAL(18,6), S.CANTIDADSALDO) AS SALDO_ACTUAL,
            ISNULL(S.VALORUNITARIO, 0) AS VALOR_UNITARIO,
            CASE 
                WHEN R.TIPO = 'S' THEN CONVERT(DECIMAL(18,6), S.CANTIDADSALDO) - CONVERT(DECIMAL(18,6), R.CANTIDAD)
                WHEN R.TIPO = 'E' THEN CONVERT(DECIMAL(18,6), S.CANTIDADSALDO) + CONVERT(DECIMAL(18,6), R.CANTIDAD)
                ELSE NULL
            END AS NUEVO_SALDO,
            CONVERT(DECIMAL(18,6), R.CANTIDAD) * ISNULL(S.VALORUNITARIO,0) AS VALOR_TOTAL,
            CASE 
                WHEN R.TIPO = 'S' THEN (CONVERT(DECIMAL(18,6), S.CANTIDADSALDO) - CONVERT(DECIMAL(18,6), R.CANTIDAD)) * ISNULL(S.VALORUNITARIO,0)
                WHEN R.TIPO = 'E' THEN (CONVERT(DECIMAL(18,6), S.CANTIDADSALDO) + CONVERT(DECIMAL(18,6), R.CANTIDAD)) * ISNULL(S.VALORUNITARIO,0)
                ELSE NULL
            END AS VALOR_TOTAL_SALDO
        FROM tmpIN_OUT_Refs R
        JOIN MM_RF RF ON RF.CODIGO = R.CODIGO
        JOIN MM_RF_STOCK S 
            ON S.IDREFERENCIA = RF.IDREFERENCIA
           AND S.ACTIVO = 1;

        ---------------------------------------------------------
        -- 2) Validaciones previas
        ---------------------------------------------------------
        -- 2.a) ¿Hay referencias sin stock activo?
        IF EXISTS (SELECT 1 FROM #Calculos WHERE IDSTOCK_ACTIVO IS NULL)
        BEGIN
            ROLLBACK TRAN;
            RAISERROR('Proceso cancelado: existen referencias sin registro activo en MM_RF_STOCK.', 16, 1);
            RETURN;
        END

        -- 2.b) ¿Algún nuevo saldo quedó negativo?
        IF EXISTS (SELECT 1 FROM #Calculos WHERE NUEVO_SALDO < 0)
        BEGIN
            ROLLBACK TRAN;
            RAISERROR('Proceso cancelado: se detectó stock negativo en el cálculo de alguna referencia.', 16, 1);
            RETURN;
        END

        ---------------------------------------------------------
        -- 3) Inactivar registros activos actuales (por IDSTOCK_ACTIVO)
        ---------------------------------------------------------
        UPDATE S
        SET S.ACTIVO = 0
        FROM MM_RF_STOCK S
        JOIN #Calculos C ON C.IDSTOCK_ACTIVO = S.IDMM_RF_STOCK;

        ---------------------------------------------------------
        -- 4) Insertar nuevos registros activos con los saldos calculados
        ---------------------------------------------------------
        INSERT INTO MM_RF_STOCK
        (
            IDREFERENCIA,
            FECHA,
            DETALLE,
            VALORUNITARIO,
            CANTIDAD,
            VALORTOTAL,
            TIPOMOVIMIENTO,
            CANTIDADSALDO,
            VALORTOTALSALDO,
            USUARIOTRCR,
            FECHATRCR,
            USUARIOTRED,
            FECHATRED,
            IDBODEGA,
            ACTIVO
        )
        SELECT
            IDREFERENCIA,
            GETDATE() AS FECHA,
            CASE WHEN TIPO = 'S' THEN 'Ajuste inventario salida' ELSE 'Ajuste inventario entrada' END AS DETALLE,
            VALOR_UNITARIO,
            CANTIDAD,
            VALOR_TOTAL,
            TIPO,
            NUEVO_SALDO,
            VALOR_TOTAL_SALDO,
            'ESPO' AS USUARIOTRCR,
            GETDATE() AS FECHATRCR,
            'ESPO' AS USUARIOTRED,
            GETDATE() AS FECHATRED,
            1 AS IDBODEGA,
            1 AS ACTIVO
        FROM #Calculos;

        COMMIT TRAN;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRAN;

        DECLARE 
            @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE(),
            @ErrSeverity INT = ERROR_SEVERITY(),
            @ErrState INT = ERROR_STATE();

        RAISERROR('Error en pr_AjusteInventarioOptimizado_v2: %s', 16, 1, @ErrMsg);
        -- Opcional: volver a lanzar el error original
        THROW;
    END CATCH;

END;
GO
