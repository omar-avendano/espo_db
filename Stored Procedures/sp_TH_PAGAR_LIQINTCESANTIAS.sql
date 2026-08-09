ALTER PROCEDURE [dbo].[sp_TH_PAGAR_LIQINTCESANTIAS]
    @IDLIQUIDACION  INT,
    @USERNAME   VARCHAR(60),
    @IDBANCO    INT,
    @FECHAPAGO  DATE,
    @MENSAJE    VARCHAR(150) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE 
            @IDMOVGC        INT,
            @ANIO        INT,
            @CONTABILIZADO  BIT = 0,
            @NUMIDENTIFICACION VARCHAR(20) = '',
            @FECHATRCR      DATE = CAST(GETDATE() AS DATE),
            @CUENTACONTABLEBANCO NVARCHAR(20) = N'11100504';

        -- 1. Validar estado de liquidación
        SELECT 
            @CONTABILIZADO = CASE WHEN ESTADO IN ('C','X') THEN 1 ELSE 0 END,
            @ANIO=PERIODO
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

        -- A. Crear UNA cabecera (GC_MOV_C) por cada Entidad
        DECLARE @NUMDOCUME INT = (SELECT ISNULL(MAX(NUMDOCUME),0) + 1 FROM GC_MOV_C WHERE CODDOCUME = 'TRA');

        INSERT INTO GC_MOV_C 
            (CODDOCUME, IDTERCERO, CODDOCUMEREL, NUMDOCUME, NUMDOCUMEREL, 
                FECHA, DESCRIPCION, PERIODO, CONTABILIZADO, DEBITO, CREDITO, 
                USUARIOTRCR, INACTIVO, FECHATRCR,IDBANCO) 
        VALUES 
            ('TRA', @NUMIDENTIFICACION, 'NOM', @NUMDOCUME, CAST(@IDLIQUIDACION AS VARCHAR(30)), 
                @FECHAPAGO, 'PAGO INTERESES DE CESANTIAS: ' + STR(@ANIO), NULL, '0', 0, 0, 
                @USERNAME, 0, @FECHATRCR, @IDBANCO);

        SET @IDMOVGC = SCOPE_IDENTITY();
        
        -- B. Insertar los detalles (GC_MOV_D) de todos los empleados de ESTA entidad
        -- Usamos un INSERT INTO ... SELECT para evitar un segundo cursor y ganar rendimiento
        INSERT INTO GC_MOV_D (IDMOVGC, IDTERCERO, NUMCUENTA, NOMCUENTA, NATURALEZA, NROASIENTO, VALOR)
        SELECT 
            @IDMOVGC,
            HV.NUMIDENTIFICACION,
            T.Cuenta,
            T.Cuenta,
            T.Tipo,
            ROW_NUMBER() OVER (ORDER BY HV.IDHOJAVIDA, T.Orden), -- Asiento consecutivo
            LIQ.VALOR_INTCESANTIAS
        FROM dbo.TH_LIQUIDACIONINTCESANTIASD LIQ
        INNER JOIN TH_HV HV ON HV.IDHOJAVIDA = LIQ.IDHOJAVIDA
        LEFT JOIN TH_DM_ENTIDAD ENT ON ENT.IDENTIDAD = HV.IDFONCES AND ENT.CODIGO = 7
        CROSS APPLY (
            SELECT N'250802' AS Cuenta, 'D' AS Tipo, 1 AS Orden UNION ALL
            SELECT N'250503', 'C', 2 UNION ALL
            SELECT N'250503', 'D', 3 UNION ALL
            SELECT @CUENTACONTABLEBANCO, 'C', 4
        ) AS T
        WHERE LIQ.IDLIQUIDACIONINTCESANTIASC = @IDLIQUIDACION;

        -- C. Marcar empleados como contabilizados
        UPDATE LIQ
        SET CONTABILIZADO = 1
        FROM TH_LIQUIDACIONINTCESANTIASD LIQ
        INNER JOIN TH_HV HV ON HV.IDHOJAVIDA = LIQ.IDHOJAVIDA
        WHERE LIQ.IDLIQUIDACIONINTCESANTIASC = @IDLIQUIDACION 

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