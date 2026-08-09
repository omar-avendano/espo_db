USE [ESPO]
GO
/****** Object:  StoredProcedure [dbo].[sp_TH_PAGAR_LIQDEFINITIVA]    Script Date: 8/8/2025 3:17:09 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[sp_TH_PAGAR_LIQDEFINITIVA]
    @IDNOMINALIQC INT,
    @USERNAME     VARCHAR(60),
    @IDBANCO INT,
    @FECHAPAGO DATE,
    @MENSAJE      VARCHAR(150) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE 
        @IDMOVGC        INT = 0,
        @BASE           INT = 0,
        @PORCENTAJE     DECIMAL(10,2) = 0,
        @IDCENTROCOSTO  INT = 0,
        @CODCENTROCOSTO INT = NULL,
        @NUMCUENTA      VARCHAR(20) = '',
        @NATURALEZA     CHAR(1) = '',
        @NROASIENTO     INT = 0,
        @ESTADO         CHAR(1) = '',
        @FECHATRCR      DATE = CAST(GETDATE() AS DATE);
        

    -- Verificar estado
    SELECT @ESTADO = ESTADO
    FROM TH_NOMINALIQC
    WHERE IDNOMINALIQC = @IDNOMINALIQC;

    IF @ESTADO = 'C'
    BEGIN
        DECLARE 
            @PERIODOPAGO   INT,
            @NUMIDENTIFICACION VARCHAR(20) = '',
            @VALOR         DECIMAL(18, 2) = 0,
            @VALORPENSION  DECIMAL(18, 2) = 0,
            @VALORSALUD    DECIMAL(18, 2) = 0,
            @DEDUCCIONES   DECIMAL(18, 2) = 0,
            @NETOPAGAR     DECIMAL(18, 2) = 0,
            @NETOPAGARDEBITO     DECIMAL(18, 2) = 0,
            @NETOPAGARCREDITO     DECIMAL(18, 2) = 0,
            @NUMDOCUME     INT = 0,
            @CODDOCUMEREL  VARCHAR(5) = N'NOM',
            @NUMDOCUMEREL  VARCHAR(30) = CAST(@IDNOMINALIQC AS VARCHAR(30)),
            @DVSUELDOB     DECIMAL(10,2) = 0,
            @DVSUBTRAN     DECIMAL(10,2) = 0,
            @PGCESANTI     DECIMAL(10,2) = 0,
            @PGINTCESA     DECIMAL(10,2) = 0,
            @PGVACACIO     DECIMAL(10,2) = 0,
            @PGPRIMASE     DECIMAL(10,2) = 0,
            @DDAUTEMPL     DECIMAL(10,2) = 0,
            @DDLIBRANZ     DECIMAL(10,2) = 0,
            @PGINDEMNI     DECIMAL(10,2) = 0,
            @POR_PENSIONEMPLEADO REAL,
            @POR_SALUDEMPLEADO   REAL,
            @IDHOJAVIDA    INT,
            @IDCONTRATOHV  INT,
            @CODIGOCONCEPTO VARCHAR(50),
            @CUENTADEBITO  VARCHAR(20),
            @CUENTACREDITO VARCHAR(20);

        DECLARE @CUENTACONTABLEBANCO NVARCHAR(20)=N'11100504';
        --Optener cuenta contable banco
        IF @IDBANCO>0
        BEGIN
            SELECT @CUENTACONTABLEBANCO =CUENTACONTABLE FROM PR_BANCO WHERE IDBANCO=@IDBANCO
        END
        
        --Fecha pago
        IF @FECHAPAGO IS NULL
        BEGIN
            SET @FECHAPAGO = CAST(GETDATE() AS DATE);
        END

        -- Crear encabezado
        SELECT @NUMDOCUME = ISNULL(MAX(NUMDOCUME),0) + 1
        FROM GC_MOV_C 
        WHERE CODDOCUME = 'TRA';

        INSERT INTO GC_MOV_C 
            (CODDOCUME, IDTERCERO, CODDOCUMEREL, NUMDOCUME, NUMDOCUMEREL, FECHA, DESCRIPCION, PERIODO, CONTABILIZADO, DEBITO, CREDITO, USUARIOTRCR, INACTIVO, FECHATRCR,IDBANCO) 
        VALUES 
            ('TRA', @NUMIDENTIFICACION, @CODDOCUMEREL, @NUMDOCUME, @NUMDOCUMEREL, @FECHAPAGO, 'CAUSACION PAGO LIQUIDACION CONTRATO', @PERIODOPAGO, '0', @NETOPAGAR, @NETOPAGAR, @USERNAME, 0, @FECHATRCR,@IDBANCO);

        SET @IDMOVGC = SCOPE_IDENTITY();

        -- Obtener parámetros
        SELECT TOP 1 
            @IDHOJAVIDA = LIQ.IDHOJAVIDA,
            @NUMIDENTIFICACION = HV.NUMIDENTIFICACION,
            @IDCONTRATOHV = CHV.IDCONTRATOHV,
            @POR_PENSIONEMPLEADO = PA.POR_PENSIONEMPLEADO,
            @POR_SALUDEMPLEADO = PA.POR_SALUDEMPLEADO
        FROM dbo.TH_NOMINALIQD LIQ
        INNER JOIN dbo.TH_CONTRATOHV CHV ON CHV.IDHOJAVIDA = LIQ.IDHOJAVIDA AND CHV.ESTADO = 1
        INNER JOIN dbo.TH_PARAMETROANUAL PA ON PA.ANIO = YEAR(@FECHATRCR)
        INNER JOIN TH_HV HV ON HV.IDHOJAVIDA = CHV.IDHOJAVIDA
        WHERE LIQ.IDNOMINALIQC = @IDNOMINALIQC;

        IF @IDHOJAVIDA > 0
        BEGIN
            -- Cargar valores de liquidación
            DECLARE CurLiquidaciones CURSOR FOR
                SELECT CODIGOCONCEPTO, SUM(VALOR) AS VALOR
                FROM TH_NOMINALIQD
                WHERE IDNOMINALIQC = @IDNOMINALIQC
                GROUP BY CODIGOCONCEPTO;

            OPEN CurLiquidaciones;
            FETCH NEXT FROM CurLiquidaciones INTO @CODIGOCONCEPTO, @VALOR;

            WHILE @@FETCH_STATUS = 0
            BEGIN
                IF @CODIGOCONCEPTO = N'DV-SUELDOB'  SET @DVSUELDOB = @VALOR;
                IF @CODIGOCONCEPTO = N'DV-SUBTRAN'  SET @DVSUBTRAN = @VALOR;
                IF @CODIGOCONCEPTO = N'PG-CESANTI'  SET @PGCESANTI = @VALOR;
                IF @CODIGOCONCEPTO = N'PG-INTCESA'  SET @PGINTCESA = @VALOR;
                IF @CODIGOCONCEPTO = N'PG-PRIMASE'  SET @PGPRIMASE = @VALOR;
                IF @CODIGOCONCEPTO = N'PG-VACACIO'  SET @PGVACACIO = @VALOR;
                IF @CODIGOCONCEPTO = N'DD-AUTEMPL'  SET @DDAUTEMPL = @VALOR;
                IF @CODIGOCONCEPTO = N'DD-LIBRANZ'  SET @DDLIBRANZ = @VALOR;
                IF @CODIGOCONCEPTO = N'PG-INDEMNI'  SET @PGINDEMNI = @VALOR;

                FETCH NEXT FROM CurLiquidaciones INTO @CODIGOCONCEPTO, @VALOR;
            END

            CLOSE CurLiquidaciones;
            DEALLOCATE CurLiquidaciones;

            -- Función para insertar Débito / Crédito

            DECLARE @InsertMovimiento TABLE (
                CuentaD VARCHAR(20),
                CuentaC VARCHAR(20),
                Valor DECIMAL(18,2)
            );

            -- Si hay sueldo básico
            IF @DVSUELDOB > 0
            BEGIN
                SET @VALORPENSION = (@DVSUELDOB * @POR_PENSIONEMPLEADO) / 100;
                SET @VALORSALUD   = (@DVSUELDOB * @POR_SALUDEMPLEADO) / 100;
                --Pendiente Otras deducciones--DD-LIBRANZ DD-AUTEMPL DD-RETEFTE
                SET @DEDUCCIONES  = @VALORPENSION + @VALORSALUD + @DDAUTEMPL;
                SET @NETOPAGARDEBITO    = (@DVSUELDOB + @DVSUBTRAN)-(@VALORPENSION + @VALORSALUD) ;
                SET @NETOPAGARCREDITO    = (@NETOPAGARDEBITO+@PGPRIMASE+@PGCESANTI+@PGINTCESA+@PGVACACIO) - (@DDAUTEMPL+@DDLIBRANZ);

                INSERT INTO @InsertMovimiento VALUES (N'250501',N'', @NETOPAGARDEBITO);
                INSERT INTO @InsertMovimiento VALUES (N'',@CUENTACONTABLEBANCO, @NETOPAGARCREDITO);
            END
            ELSE
            BEGIN
                
                SET @NETOPAGARCREDITO    = (@PGPRIMASE+@PGCESANTI+@PGINTCESA+@PGVACACIO) - (@DDAUTEMPL+@DDLIBRANZ);
                INSERT INTO @InsertMovimiento VALUES (N'',@CUENTACONTABLEBANCO, @NETOPAGARCREDITO);
            END

            IF @PGPRIMASE > 0 INSERT INTO @InsertMovimiento VALUES (N'250506', N'', @PGPRIMASE);
            IF @PGCESANTI > 0 INSERT INTO @InsertMovimiento VALUES (N'250502', N'', @PGCESANTI);
            IF @PGINTCESA > 0 INSERT INTO @InsertMovimiento VALUES (N'250503', N'', @PGINTCESA);
            IF @PGVACACIO > 0 INSERT INTO @InsertMovimiento VALUES (N'250504', N'', @PGVACACIO);
            IF @PGINDEMNI > 0 INSERT INTO @InsertMovimiento VALUES (N'250508', @CUENTACONTABLEBANCO, @PGINDEMNI);
            IF @DDAUTEMPL > 0 INSERT INTO @InsertMovimiento VALUES (N'',N'242541', @DDAUTEMPL);
            IF @DDLIBRANZ > 0 INSERT INTO @InsertMovimiento VALUES (N'',N'242535', @DDLIBRANZ);

            -- Insertar movimientos en GC_MOV_D
            DECLARE MovCur CURSOR FOR
                SELECT CuentaD, CuentaC, Valor FROM @InsertMovimiento;

            OPEN MovCur;
            FETCH NEXT FROM MovCur INTO @CUENTADEBITO, @CUENTACREDITO, @VALOR;

            WHILE @@FETCH_STATUS = 0
            BEGIN
                SET @NROASIENTO = @NROASIENTO + 1;
                
                --PRINT 'ID: '+str(@IDMOVGC)+ ' Iden:' +STR(@NUMIDENTIFICACION)+' cta d:'+@CUENTADEBITO+' cta c:'+@CUENTACREDITO + 'valor: '+str( @VALOR)
                -- Débito
                IF @CUENTADEBITO <> N''
                BEGIN
                    
                    INSERT INTO GC_MOV_D 
                        (IDMOVGC, IDTERCERO, IDCENTROCOSTO, CODCENTROCOSTO, NUMCUENTA, NOMCUENTA, NATURALEZA, NROASIENTO, DESCRIPCION, VALOR, BASERET, RETENCION, PERIODO)
                    VALUES 
                        (@IDMOVGC, @NUMIDENTIFICACION, @IDCENTROCOSTO, @CODCENTROCOSTO, @CUENTADEBITO, @CUENTADEBITO, 'D', @NROASIENTO, '', @VALOR, @BASE, @PORCENTAJE, @PERIODOPAGO);
                END

                -- Crédito
                IF @CUENTACREDITO <> N''
                BEGIN
                    INSERT INTO GC_MOV_D 
                        (IDMOVGC, IDTERCERO, IDCENTROCOSTO, CODCENTROCOSTO, NUMCUENTA, NOMCUENTA, NATURALEZA, NROASIENTO, DESCRIPCION, VALOR, BASERET, RETENCION, PERIODO)
                    VALUES 
                        (@IDMOVGC, @NUMIDENTIFICACION, @IDCENTROCOSTO, @CODCENTROCOSTO, @CUENTACREDITO, @CUENTACREDITO, 'C', @NROASIENTO, '', @VALOR, @BASE, @PORCENTAJE, @PERIODOPAGO);
                END

                FETCH NEXT FROM MovCur INTO @CUENTADEBITO, @CUENTACREDITO, @VALOR;
            END

            CLOSE MovCur;
            DEALLOCATE MovCur;

            --INACTIVAR CONTRATO
           /*  UPDATE dbo.TH_CONTRATOHV 
                SET ESTADO=0
            WHERE IDHOJAVIDA=@IDHOJAVIDA AND ESTADO=1 */
            --INACTIVAR USUARIO
            UPDATE TH_HV SET ESTADOHV=0 WHERE IDHOJAVIDA=@IDHOJAVIDA
            --INACTIVAR NOVEDADES 
            UPDATE TH_NOVEDAD SET ESTADO=0 WHERE IDHOJAVIDA=@IDHOJAVIDA
            
        END

        -- Cambiar estado
        UPDATE TH_NOMINALIQC
        SET ESTADO = 'X'
        WHERE IDNOMINALIQC = @IDNOMINALIQC;

        SET @MENSAJE = 'Pago creado correctamente';
    END
END
