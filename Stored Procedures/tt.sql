USE [ESPO]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[sp_TH_CONTABILIZAR_LIQVACACIONES]
    @IDLIQUIDACIONVACACIONES INT,
    @USERNAME VARCHAR(60),
    @MENSAJE VARCHAR(150) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -------------------------------------------------------------------------
    -- Variables principales
    -------------------------------------------------------------------------
    DECLARE
        @CONTABILIZADO INT = 0,
        @IDHOJAVIDA INT = 0,
        @NUMIDENTIFICACION VARCHAR(20),
        @FECHAINICIO DATE,
        @FECHATRCR DATE = CAST(GETDATE() AS DATE),

        -- Datos necesarios para la contabilización
        @DVSUELDOB DECIMAL(18,2) = 0,
        @CUENTADEBITO VARCHAR(20),
        @CUENTACREDITO VARCHAR(20),

        -- Cabecera de la liquidación contable
        @IDNOMINALIQC INT,
        @PERIODO INT,

        -- Control del número de asiento
        @NROASIENTO INT = 0;

    -------------------------------------------------------------------------
    -- 1. Validar si la liquidación de vacaciones ya fue contabilizada
    -------------------------------------------------------------------------
    SELECT
        @CONTABILIZADO = ISNULL(CONTABILIZADO, 0)
    FROM dbo.TH_LIQUIDACIONVACACIONES
    WHERE IDLIQUIDACIONVACACIONES = @IDLIQUIDACIONVACACIONES;

    -------------------------------------------------------------------------
    -- Si ya está contabilizada, no se vuelve a procesar
    -------------------------------------------------------------------------
    IF @CONTABILIZADO = 1
    BEGIN
        SET @MENSAJE = 'La liquidación de vacaciones ya fue contabilizada';
        RETURN;
    END;


    -------------------------------------------------------------------------
    -- 2. Obtener información necesaria de la liquidación y del empleado
    --
    -- Solo se conservan los campos que realmente se utilizan posteriormente.
    -------------------------------------------------------------------------
    SELECT TOP (1)
        @IDHOJAVIDA = LIQ.IDHOJAVIDA,
        @NUMIDENTIFICACION = HV.NUMIDENTIFICACION,
        @DVSUELDOB = ISNULL(LIQ.DEVENGADO, 0),
        @FECHAINICIO = LIQ.FECHA_INICIO
    FROM dbo.TH_LIQUIDACIONVACACIONES AS LIQ
    INNER JOIN dbo.TH_CONTRATOHV AS CHV
        ON CHV.IDHOJAVIDA = LIQ.IDHOJAVIDA
       AND CHV.ESTADO = 1
    INNER JOIN dbo.TH_HV AS HV
        ON HV.IDHOJAVIDA = CHV.IDHOJAVIDA
    WHERE LIQ.IDLIQUIDACIONVACACIONES = @IDLIQUIDACIONVACACIONES;


    -------------------------------------------------------------------------
    -- 3. Validar que exista la información necesaria del empleado/contrato
    -------------------------------------------------------------------------
    IF ISNULL(@IDHOJAVIDA, 0) = 0
    BEGIN
        SET @MENSAJE =
            'Revise los parametros de contrato y de empleado ya que no estan bien y no se puede ejecutar la liquidación';

        RETURN;
    END;


    -------------------------------------------------------------------------
    -- 4. Obtener el período contable.
    --
    -- EOMONTH devuelve el último día del mes de la fecha de inicio.
    -- Formato YYYYMMDD convertido a INT.
    -------------------------------------------------------------------------
    SET @PERIODO =
        CONVERT(INT, CONVERT(CHAR(8), EOMONTH(@FECHAINICIO), 112));


    -------------------------------------------------------------------------
    -- 5. Crear cabecera de la liquidación contable
    -------------------------------------------------------------------------
    BEGIN TRY

        BEGIN TRANSACTION;


        INSERT INTO dbo.TH_NOMINALIQC
        (
            VALOR,
            USUARIOLIQUIDO,
            PERIODO,
            FECHALIQUIDACION,
            FECHAMOVIMIENTO,
            MOD_ORIGEN,
            ESTADO,
            DESCRIPCION,
            EMPLEADOS_LIQUIDADOS,
            OBSERVACIONESLIQUIDACION,
            USUARIOTRCR,
            FECHATRCR,
            USUARIOTRED,
            FECHATRED,
            IDBANCO
        )
        VALUES
        (
            0,
            @USERNAME,
            @PERIODO,
            @FECHAINICIO,
            @FECHATRCR,
            'LIQVAC',
            'L',
            'Liquidación de Vacaciones',
            1,
            'Liquidación de Vacaciones',
            @USERNAME,
            @FECHATRCR,
            @USERNAME,
            @FECHATRCR,
            NULL
        );


        ---------------------------------------------------------------------
        -- Obtener el ID generado para la cabecera contable
        ---------------------------------------------------------------------
        SET @IDNOMINALIQC = SCOPE_IDENTITY();


        ---------------------------------------------------------------------
        -- 6. Crear movimientos contables
        --
        -- Actualmente el procedimiento solamente genera un movimiento:
        --
        --   Débito  : 250803
        --   Crédito : 250504
        --
        -- Por lo tanto no se requiere tabla variable ni cursor.
        ---------------------------------------------------------------------
        IF @DVSUELDOB > 0
        BEGIN

            SET @NROASIENTO = 1;

            SET @CUENTADEBITO = '250803';
            SET @CUENTACREDITO = '250504';


            -----------------------------------------------------------------
            -- Movimiento Débito
            -----------------------------------------------------------------
            INSERT INTO dbo.TH_NOMINAMOVCNT
            (
                IDNOMINALIQC,
                NUMASIENTO,
                COD_TERCERO,
                CENTRO,
                TIPO_ASIENTO,
                COD_CUENTA,
                DESCRIPCION,
                NATURALEZA,
                BASE,
                VALOR,
                CEN_SUB,
                FECHA_ENV,
                FECHA_LIQ,
                CONTABILIZADO,
                MOD_ORIGEN,
                FECHATRCR,
                USUARIOTRCR,
                FECHATRED,
                USUARIOTRED
            )
            VALUES
            (
                @IDNOMINALIQC,
                @NROASIENTO,
                @NUMIDENTIFICACION,
                '',
                'N',
                @CUENTADEBITO,
                @CUENTADEBITO,
                'D',
                @DVSUELDOB,
                @DVSUELDOB,
                '',
                @FECHATRCR,
                @FECHATRCR,
                0,
                'LIQNOM',
                @FECHATRCR,
                @USERNAME,
                @FECHATRCR,
                @USERNAME
            );


            -----------------------------------------------------------------
            -- Movimiento Crédito
            --
            -- IMPORTANTE:
            -- En el SP original se utilizaba @CUENTADEBITO también aquí.
            -- Se corrige para utilizar @CUENTACREDITO.
            -----------------------------------------------------------------
            INSERT INTO dbo.TH_NOMINAMOVCNT
            (
                IDNOMINALIQC,
                NUMASIENTO,
                COD_TERCERO,
                CENTRO,
                TIPO_ASIENTO,
                COD_CUENTA,
                DESCRIPCION,
                NATURALEZA,
                BASE,
                VALOR,
                CEN_SUB,
                FECHA_ENV,
                FECHA_LIQ,
                CONTABILIZADO,
                MOD_ORIGEN,
                FECHATRCR,
                USUARIOTRCR,
                FECHATRED,
                USUARIOTRED
            )
            VALUES
            (
                @IDNOMINALIQC,
                @NROASIENTO,
                @NUMIDENTIFICACION,
                '',
                'N',
                @CUENTACREDITO,       -- Corrección respecto al SP original
                @CUENTACREDITO,       -- Corrección respecto al SP original
                'C',
                @DVSUELDOB,
                @DVSUELDOB,
                '',
                @FECHATRCR,
                @FECHATRCR,
                0,
                'LIQNOM',
                @FECHATRCR,
                @USERNAME,
                @FECHATRCR,
                @USERNAME
            );

        END;


        ---------------------------------------------------------------------
        -- 7. Marcar la liquidación como contabilizada
        ---------------------------------------------------------------------
        UPDATE dbo.TH_LIQUIDACIONVACACIONES
        SET CONTABILIZADO = 1
        WHERE IDLIQUIDACIONVACACIONES = @IDLIQUIDACIONVACACIONES;


        ---------------------------------------------------------------------
        -- 8. Confirmar todos los cambios
        ---------------------------------------------------------------------
        COMMIT TRANSACTION;


        ---------------------------------------------------------------------
        -- Mensaje de resultado exitoso
        ---------------------------------------------------------------------
        SET @MENSAJE = 'Contabilización creada correctamente';

    END TRY
    BEGIN CATCH

        ---------------------------------------------------------------------
        -- Si ocurre un error, deshacer todos los cambios realizados
        ---------------------------------------------------------------------
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;


        ---------------------------------------------------------------------
        -- Retornar el mensaje de error
        ---------------------------------------------------------------------
        SET @MENSAJE =
            LEFT(
                'Error durante la contabilización: ' + ERROR_MESSAGE(),
                150
            );

    END CATCH;

END
GO