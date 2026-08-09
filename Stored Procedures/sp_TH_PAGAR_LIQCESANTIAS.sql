ALTER PROCEDURE [dbo].[sp_TH_PAGAR_LIQCESANTIAS]
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
            @IDMOVGC        INT,
            @CONTABILIZADO  BIT = 0,
            @FECHATRCR      DATE = CAST(GETDATE() AS DATE),
            @CUENTACONTABLEBANCO NVARCHAR(20) = N'11100504';

        -- 1. Validar estado de liquidación
        SELECT 
            @CONTABILIZADO = CASE WHEN ESTADO IN ('C','X') THEN 1 ELSE 0 END
        FROM TH_NOMINALIQC
        WHERE IDNOMINALIQC = @IDLIQUIDACION;

        IF @CONTABILIZADO = 1
        BEGIN
            SET @MENSAJE = 'La liquidación ya está contabilizada';
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        -- 2. Obtener cuenta contable banco
        IF EXISTS(SELECT 1 FROM PR_BANCO WHERE IDBANCO = @IDBANCO)
            SELECT @CUENTACONTABLEBANCO = CUENTACONTABLE FROM PR_BANCO WHERE IDBANCO = @IDBANCO;

        IF @FECHAPAGO IS NULL SET @FECHAPAGO = @FECHATRCR;

        -- 3. CURSOR PRINCIPAL: Agrupado por Entidad
        -- Aquí definimos qué entidad recibirá el pago
        DECLARE @IDENTIDAD_LOOP INT, @NIT_ENTIDAD VARCHAR(20), @TOTAL_ENTIDAD DECIMAL(12,2);

        DECLARE cursor_Entidades CURSOR FOR
        SELECT 
            HV.IDFONCES,
            MAX(ENT.NIT), -- Nit de la entidad o del empleado si no tiene
            SUM(LIQ.VALOR_CESANTIAS)
        FROM dbo.TH_LIQUIDACIONCESANTIASD LIQ
        INNER JOIN TH_HV HV ON HV.IDHOJAVIDA = LIQ.IDHOJAVIDA
        LEFT JOIN TH_DM_ENTIDAD ENT ON ENT.IDENTIDAD = HV.IDFONCES AND ENT.CODIGO = 7
        WHERE LIQ.IDLIQUIDACIONCESANTIASC = @IDLIQUIDACION
        GROUP BY HV.IDFONCES;

        OPEN cursor_Entidades;
        FETCH NEXT FROM cursor_Entidades INTO @IDENTIDAD_LOOP, @NIT_ENTIDAD, @TOTAL_ENTIDAD;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- A. Crear UNA cabecera (GC_MOV_C) por cada Entidad
            DECLARE @NUMDOCUME INT = (SELECT ISNULL(MAX(NUMDOCUME),0) + 1 FROM GC_MOV_C WHERE CODDOCUME = 'TRA');

            INSERT INTO GC_MOV_C 
                (CODDOCUME, IDTERCERO, CODDOCUMEREL, NUMDOCUME, NUMDOCUMEREL, 
                 FECHA, DESCRIPCION, PERIODO, CONTABILIZADO, DEBITO, CREDITO, 
                 USUARIOTRCR, INACTIVO, FECHATRCR) 
            VALUES 
                ('TRA', @NIT_ENTIDAD, 'NOM', @NUMDOCUME, CAST(@IDLIQUIDACION AS VARCHAR(30)), 
                 @FECHAPAGO, 'PAGO CESANTIAS ENTIDAD: ' + @NIT_ENTIDAD, NULL, '0', @TOTAL_ENTIDAD, @TOTAL_ENTIDAD, 
                 @USERNAME, 0, @FECHATRCR);

            SET @IDMOVGC = SCOPE_IDENTITY();

            -- B. Insertar los detalles (GC_MOV_D) de todos los empleados de ESTA entidad
            -- Usamos un INSERT INTO ... SELECT para evitar un segundo cursor y ganar rendimiento
            INSERT INTO GC_MOV_D (IDMOVGC, IDTERCERO, NUMCUENTA, NOMCUENTA, NATURALEZA, NROASIENTO, VALOR)
            SELECT 
                @IDMOVGC,
                case when T.Cuenta=@CUENTACONTABLEBANCO then @NIT_ENTIDAD else HV.NUMIDENTIFICACION end AS IDTERCERO,
                T.Cuenta,
                T.Cuenta,
                T.Tipo,
                ROW_NUMBER() OVER (ORDER BY HV.IDHOJAVIDA, T.Orden), -- Asiento consecutivo
                LIQ.VALOR_CESANTIAS
            FROM dbo.TH_LIQUIDACIONCESANTIASD LIQ
            INNER JOIN TH_HV HV ON HV.IDHOJAVIDA = LIQ.IDHOJAVIDA
            LEFT JOIN TH_DM_ENTIDAD ENT ON ENT.IDENTIDAD = HV.IDFONCES AND ENT.CODIGO = 7
            CROSS APPLY (
                SELECT N'250801' AS Cuenta, 'D' AS Tipo, 1 AS Orden UNION ALL
                SELECT N'250502', 'C', 2 UNION ALL
                SELECT N'250502', 'D', 3 UNION ALL
                SELECT @CUENTACONTABLEBANCO, 'C', 4
            ) AS T
            WHERE LIQ.IDLIQUIDACIONCESANTIASC = @IDLIQUIDACION
              AND HV.IDFONCES = @IDENTIDAD_LOOP;

            -- C. Marcar empleados como contabilizados
            UPDATE LIQ
            SET CONTABILIZADO = 1
            FROM TH_LIQUIDACIONCESANTIASD LIQ
            INNER JOIN TH_HV HV ON HV.IDHOJAVIDA = LIQ.IDHOJAVIDA
            WHERE LIQ.IDLIQUIDACIONCESANTIASC = @IDLIQUIDACION 
              AND HV.IDFONCES = @IDENTIDAD_LOOP;

            FETCH NEXT FROM cursor_Entidades INTO @IDENTIDAD_LOOP, @NIT_ENTIDAD, @TOTAL_ENTIDAD;
        END

        CLOSE cursor_Entidades;
        DEALLOCATE cursor_Entidades;

        -- 4. Cerrar liquidación principal
        UPDATE TH_NOMINALIQC
        SET ESTADO = 'X', IDBANCO = @IDBANCO
        WHERE IDNOMINALIQC = @IDLIQUIDACION;

        SET @MENSAJE = 'Proceso completado: Se crearon pagos por entidad.';
        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @MENSAJE = 'Error: ' + ERROR_MESSAGE();
    END CATCH
END