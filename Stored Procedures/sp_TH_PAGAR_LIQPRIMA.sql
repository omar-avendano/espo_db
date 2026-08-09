ALTER PROCEDURE [dbo].[sp_TH_PAGAR_LIQPRIMA]
    @IDLIQUIDACION INT,
    @USERNAME     VARCHAR(60),
    @IDBANCO INT,
    @FECHAPAGO DATE,
    @MENSAJE      VARCHAR(150) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE 
            @IDMOVGC        INT = 0,
            @NROASIENTO     INT = 0,
            @CONTABILIZADO  BIT = 0,
            @NETOPAGAR      DECIMAL(12, 2) = 0,
            @FECHATRCR      DATE = CAST(GETDATE() AS DATE),
            @CUENTACONTABLEBANCO NVARCHAR(20) = N'11100504';

        -- Validar estado de liquidación
        SELECT 
            @CONTABILIZADO = CASE WHEN ESTADO IN ('C','X') THEN 1 ELSE 0 END,
            @NETOPAGAR = VALOR
        FROM TH_NOMINALIQC
        WHERE IDNOMINALIQC = @IDLIQUIDACION;

        IF @CONTABILIZADO = 1
        BEGIN
            SET @MENSAJE = 'La liquidación ya está contabilizada';
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        -- Obtener cuenta contable banco
        IF @IDBANCO > 0
            SELECT @CUENTACONTABLEBANCO = CUENTACONTABLE 
            FROM PR_BANCO 
            WHERE IDBANCO = @IDBANCO;

        -- Fecha pago
        IF @FECHAPAGO IS NULL
            SET @FECHAPAGO = @FECHATRCR;

        -- Crear encabezado GC_MOV_C
        DECLARE @NUMDOCUME INT = (SELECT ISNULL(MAX(NUMDOCUME),0) + 1 
                                  FROM GC_MOV_C WHERE CODDOCUME = 'TRA');

        INSERT INTO GC_MOV_C 
            (CODDOCUME, IDTERCERO, CODDOCUMEREL, NUMDOCUME, NUMDOCUMEREL, 
             FECHA, DESCRIPCION, PERIODO, CONTABILIZADO, DEBITO, CREDITO, 
             USUARIOTRCR, INACTIVO, FECHATRCR) 
        VALUES 
            ('TRA', NULL, 'NOM', @NUMDOCUME, CAST(@IDLIQUIDACION AS VARCHAR(30)), 
             @FECHAPAGO, 'CAUSACION PAGO LIQUIDACION PRIMA', NULL, '0', @NETOPAGAR, @NETOPAGAR, 
             @USERNAME, 0, @FECHATRCR);

        SET @IDMOVGC = SCOPE_IDENTITY();

        -- Cursor para empleados
        DECLARE cursor_PagoPrima CURSOR FOR
        SELECT 
            LIQ.IDHOJAVIDA,
            HV.NUMIDENTIFICACION,           
            LIQ.VALOR_PRIMA
        FROM dbo.TH_LIQUIDACIONPRIMAD LIQ
        INNER JOIN TH_HV HV ON HV.IDHOJAVIDA = LIQ.IDHOJAVIDA
        WHERE LIQ.IDLIQUIDACIONPRIMAC = @IDLIQUIDACION
        AND HV.IDHOJAVIDA NOT IN (241,199);  -- Filtrar empleados específicos

        DECLARE @IDHOJAVIDA INT, 
                @NUMIDENTIFICACION VARCHAR(20), 
                @VALORPRIMA DECIMAL(12,2);

        OPEN cursor_PagoPrima;
        FETCH NEXT FROM cursor_PagoPrima INTO @IDHOJAVIDA, @NUMIDENTIFICACION, @VALORPRIMA;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF @IDHOJAVIDA > 0 AND @VALORPRIMA > 0
            BEGIN
                SET @NROASIENTO = @NROASIENTO + 1;
                -- Insertar movimientos contables (4 asientos)
                INSERT INTO GC_MOV_D
                    (IDMOVGC, IDTERCERO, NUMCUENTA, NOMCUENTA, NATURALEZA, 
                     NROASIENTO, VALOR)
                SELECT @IDMOVGC, @NUMIDENTIFICACION, Cuenta, Cuenta, Tipo, 
                       ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) + @NROASIENTO, Valor
                FROM (
                    SELECT N'250804' AS Cuenta, 'D' AS Tipo, @VALORPRIMA AS Valor
                    UNION ALL
                    SELECT N'250506', 'C', @VALORPRIMA
                    UNION ALL
                    SELECT N'250506', 'D', @VALORPRIMA
                    UNION ALL
                    SELECT @CUENTACONTABLEBANCO, 'C', @VALORPRIMA
                ) Movs;

                -- Marcar liq contabilizado
                UPDATE TH_LIQUIDACIONPRIMAD
                SET CONTABILIZADO = 1
                WHERE IDLIQUIDACIONPRIMAC = @IDLIQUIDACION
                  AND IDHOJAVIDA = @IDHOJAVIDA;

                SET @MENSAJE = 'Pago creado correctamente';
            END
            ELSE
            BEGIN
                SET @MENSAJE = 'Revise empleados: no se puede ejecutar la liquidación';
                ROLLBACK TRANSACTION;
                CLOSE cursor_PagoPrima; DEALLOCATE cursor_PagoPrima;
                RETURN;
            END

            FETCH NEXT FROM cursor_PagoPrima INTO @IDHOJAVIDA, @NUMIDENTIFICACION, @VALORPRIMA;
        END

        CLOSE cursor_PagoPrima;
        DEALLOCATE cursor_PagoPrima;

        -- Cerrar liquidación principal
        UPDATE TH_NOMINALIQC
        SET ESTADO = 'X'
        WHERE IDNOMINALIQC = @IDLIQUIDACION;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;

        SET @MENSAJE = 'Error en la ejecución: ' + ERROR_MESSAGE();
    END CATCH
END