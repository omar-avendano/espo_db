SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO
--[dbo].[sp_TH_PAGAR_LIQVACACIONES] 492,'2026-06-10',1,'ESPO',''
ALTER PROCEDURE [dbo].[sp_TH_PAGAR_LIQVACACIONES]
    @IDLIQUIDACIONVACACIONES INT,
    @FECHA_PAGO DATE,
    @IDBANCO INT,
    @USERNAME     VARCHAR(60),
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
        @CONTABILIZADO  INT = 0,        
        @PAGADO  INT = 0,        
        @SALARIOMINIMOMES decimal(10,2), 
        @FECHATRCR      DATE = CAST(GETDATE() AS DATE);

    -- Verificar CONTABILIZADO
    SELECT @CONTABILIZADO = CONTABILIZADO
    FROM TH_LIQUIDACIONVACACIONES
    WHERE IDLIQUIDACIONVACACIONES = @IDLIQUIDACIONVACACIONES;

    IF @CONTABILIZADO = 1 AND @PAGADO=0
    BEGIN
        DECLARE 
            @PERIODOPAGO   INT,
            @NUMIDENTIFICACION VARCHAR(20) = '',
            @VALOR         DECIMAL(18, 2) = 0,
            @VALORPENSION  DECIMAL(18, 2) = 0,
            @VALORSOLIDARIDAD  DECIMAL(18, 2) = 0,
            @VALORSALUD    DECIMAL(18, 2) = 0,
            @DEDUCCIONES   DECIMAL(18, 2) = 0,
            @NETOPAGAR     DECIMAL(18, 2) = 0,
            @NETOPAGARDEBITO     DECIMAL(18, 2) = 0,
            @NETOPAGARCREDITO     DECIMAL(18, 2) = 0,
            @NUMDOCUME     INT = 0,
            @CODDOCUMEREL  VARCHAR(5) = N'NOM',
            @NUMDOCUMEREL  VARCHAR(30) = CAST(@IDLIQUIDACIONVACACIONES AS VARCHAR(30)),
            @SALARIO     DECIMAL(10,2) = 0,
            @SALARIOVAC     DECIMAL(10,2) = 0,
            @AUXTRANSPORTE DECIMAL(10,2) = 0,
            @AUXTRANSPORTEVAC DECIMAL(10,2) = 0,
            @DVSUELDOB     DECIMAL(10,2) = 0,
            @DVSUBTRAN     DECIMAL(10,2) = 0,
            @PGCESANTI     DECIMAL(10,2) = 0,
            @PGINTCESA     DECIMAL(10,2) = 0,
            @PGVACACIO     DECIMAL(10,2) = 0,
            @PGPRIMASE     DECIMAL(10,2) = 0,
            @DDAUTEMPL     DECIMAL(10,2) = 0,
            @POR_PENSIONES REAL,
            @POR_SALUD REAL,
            @POR_INTCESANTIAS REAL,
			@POR_VACACIONES REAL,
			@POR_CESANTIAS REAL,
            @POR_PENSIONEMPLEADO REAL,
            @POR_SOLIDARIDAD REAL=1,
            @POR_SALUDEMPLEADO   REAL,
            @POR_PRIMA   REAL,
            @IDHOJAVIDA    INT,
            @IDCONTRATOHV  INT,
            @DIASVACACIONES  INT,
            @CUENTABASE  VARCHAR(5)=N'',
            @CODIGOCONCEPTO VARCHAR(50),
            @CUENTADEBITO  VARCHAR(20),
            @CUENTACREDITO VARCHAR(20);

        DECLARE @CUENTACONTABLEBANCO NVARCHAR(20)=N'11100504';
        --Optener cuenta contable banco
        IF @IDBANCO>0
        BEGIN
            SELECT @CUENTACONTABLEBANCO =CUENTACONTABLE FROM PR_BANCO WHERE IDBANCO=@IDBANCO
        END

        -- Crear encabezado
        SELECT @NUMDOCUME = ISNULL(MAX(NUMDOCUME),0) + 1
        FROM GC_MOV_C 
        WHERE CODDOCUME = 'TRA';

        INSERT INTO GC_MOV_C 
            (CODDOCUME, IDTERCERO, CODDOCUMEREL, NUMDOCUME, NUMDOCUMEREL, FECHA, DESCRIPCION, PERIODO, CONTABILIZADO, DEBITO, CREDITO, USUARIOTRCR, INACTIVO, FECHATRCR,IDBANCO) 
        VALUES 
            ('TRA', @NUMIDENTIFICACION, @CODDOCUMEREL, @NUMDOCUME, @NUMDOCUMEREL, @FECHA_PAGO, 'CAUSACION PAGO LIQUIDACION VACACIONES', @PERIODOPAGO, '0', @NETOPAGAR, @NETOPAGAR, @USERNAME, 0, @FECHATRCR, @IDBANCO);

        SET @IDMOVGC = SCOPE_IDENTITY();

        -- Obtener parámetros
        SELECT TOP 1 
            @IDHOJAVIDA = LIQ.IDHOJAVIDA,
            @NUMIDENTIFICACION = HV.NUMIDENTIFICACION,
            @IDCONTRATOHV = CHV.IDCONTRATOHV,
            @POR_PENSIONEMPLEADO = PA.POR_PENSIONEMPLEADO,
            @POR_SALUDEMPLEADO = PA.POR_SALUDEMPLEADO,
            @POR_PENSIONES=PA.POR_PENSIONES,
            @POR_SALUD=PA.POR_SALUD,
			@POR_CESANTIAS=PA.POR_CESANTIAS,
            @POR_VACACIONES=PA.POR_VACACIONES,
            @POR_INTCESANTIAS=PA.INT_CESANTIAS,
            @POR_PRIMA=PA.POR_PRIMA,
            @DVSUELDOB=DEVENGADO,
            @SALARIO=CHV.SALARIO,
			@AUXTRANSPORTE=IIF(CHV.SUBSIDIOTRANSPORTE=1,PA.SUBSIDIOTRANSPORTE,0),
            @DIASVACACIONES=DIAS_REAL,
            @CUENTABASE=CHV.CUENTABASE,
            @SALARIOMINIMOMES=PA.SALARIOMINIMO
        FROM dbo.TH_LIQUIDACIONVACACIONES LIQ
        INNER JOIN dbo.TH_CONTRATOHV CHV ON CHV.IDHOJAVIDA = LIQ.IDHOJAVIDA AND CHV.ESTADO = 1
        INNER JOIN dbo.TH_PARAMETROANUAL PA ON PA.ANIO = YEAR(@FECHATRCR)
        INNER JOIN TH_HV HV ON HV.IDHOJAVIDA = CHV.IDHOJAVIDA
        WHERE LIQ.IDLIQUIDACIONVACACIONES = @IDLIQUIDACIONVACACIONES;

        IF @IDHOJAVIDA > 0
        BEGIN
            -- Función para insertar Débito / Crédito
            DECLARE @InsertMovimiento TABLE (
                CuentaD VARCHAR(20),
                CuentaC VARCHAR(20),
                Valor DECIMAL(18,2)
            );

            --Paso 1 Vacaciones
            
            SET @SALARIOVAC = (@SALARIO/30*@DIASVACACIONES);
            SET @AUXTRANSPORTEVAC = (@AUXTRANSPORTE/30*@DIASVACACIONES);

            --IF @DEVENGADO>0 SET @DVSUELDOB=@DEVENGADO;

            IF @DVSUELDOB > 0 INSERT INTO @InsertMovimiento VALUES (N'250803', N'250504', @DVSUELDOB);

            --Paso 2 Pago

            IF @DVSUELDOB > 0 INSERT INTO @InsertMovimiento VALUES (N'250504', N'', @DVSUELDOB);

            SET @VALORPENSION = (@DVSUELDOB * @POR_PENSIONEMPLEADO) / 100;
            IF @VALORPENSION > 0 INSERT INTO @InsertMovimiento VALUES (N'', N'242518', @VALORPENSION);

            IF (@DVSUELDOB/@SALARIOMINIMOMES) >4.00
            BEGIN
                SET @VALORSOLIDARIDAD = (@DVSUELDOB * @POR_SOLIDARIDAD) / 100;
                INSERT INTO @InsertMovimiento VALUES (N'', N'242518', @VALORSOLIDARIDAD);
            END

            SET @VALORSALUD   = (@DVSUELDOB * @POR_SALUDEMPLEADO) / 100;
            IF @VALORSALUD > 0 INSERT INTO @InsertMovimiento VALUES (N'', N'242519', @VALORSALUD);
            
            --Banco
            SET @NETOPAGARCREDITO  = (@DVSUELDOB )-(@VALORPENSION + @VALORSALUD + @VALORSOLIDARIDAD)
            INSERT INTO @InsertMovimiento VALUES (N'',@CUENTACONTABLEBANCO, @NETOPAGARCREDITO);         

            /* Seccion que ahora se calculara en cada porcion de la quincena
            --Prima
            SET @PGPRIMASE=(@SALARIOVAC+@AUXTRANSPORTEVAC)*@POR_PRIMA / 100;
            IF @PGPRIMASE > 0 INSERT INTO @InsertMovimiento VALUES (N'750552', N'250801', @PGPRIMASE);250804

            --Cesantias
            SET @PGCESANTI=((@SALARIOVAC+@AUXTRANSPORTEVAC)*@POR_CESANTIAS) / 100;
            IF @PGCESANTI > 0 INSERT INTO @InsertMovimiento VALUES (N'750524', N'250802', @PGCESANTI);250801

            --Int Cesantias
            SET @PGINTCESA=(@PGCESANTI*@POR_INTCESANTIAS) / 100;
            IF @PGINTCESA > 0 INSERT INTO @InsertMovimiento VALUES (N'750525', N'250802', @PGINTCESA);

            --Vacaciones
            SET @PGVACACIO=(@SALARIOVAC*@POR_VACACIONES) / 100;
            IF @PGVACACIO > 0 INSERT INTO @InsertMovimiento VALUES (N'750518', N'250803', @PGVACACIO); */

            --Pension y Salud
                
            IF @CUENTABASE='5' SET @CUENTACREDITO=N'510307' ELSE SET @CUENTACREDITO=N'750534'
            IF @VALORPENSION > 0 INSERT INTO @InsertMovimiento VALUES (N'242518',@CUENTACREDITO, @VALORPENSION);

            --Solidaridad
            IF @VALORSOLIDARIDAD > 0 INSERT INTO @InsertMovimiento VALUES (N'242518',@CUENTACREDITO, @VALORSOLIDARIDAD);


            IF @CUENTABASE='5' SET @CUENTACREDITO=N'510303' ELSE SET @CUENTACREDITO=N'750537';
            IF @VALORSALUD > 0 INSERT INTO @InsertMovimiento VALUES (N'242519', @CUENTACREDITO, @VALORSALUD);

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

            -- Cambiar estado
            UPDATE TH_LIQUIDACIONVACACIONES
            SET PAGADO = 1
            WHERE IDLIQUIDACIONVACACIONES = @IDLIQUIDACIONVACACIONES;

            SET @MENSAJE = 'Pago creado correctamente';
           
        END
        ELSE
        BEGIN
            SET @MENSAJE = 'Revise los parametros de contrato y de empleado ya que no estan bien y no se puede ejecutar la liquidación ';
        END

    END

END
GO