SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO
ALTER PROCEDURE [dbo].[sp_TH_LIQDEFINITIVA]
@IDHOJAVIDA INT,
@FECHARETIRO DATE,
@SINJUSTACAUSA INT,
@USERNAME VARCHAR(60) ,
@OBSERVACIONES NVARCHAR(MAX),
@MENSAJE varchar(150) OUTPUT,
@IDNOMINALIQC INT =0 OUTPUT
AS
BEGIN
SET NOCOUNT ON
	--Variables Periodo
    DECLARE 
    @ERROR INT            =0 ,
    @IDLIQUIDACIONDEFINITIVA INT            =0 ,
    @IDCONTRATOHV INT                       =0 ,
    @FECHAINICIOCONTRATO DATE               =NULL ,
    @FECHAFINCONTRATO DATE               =NULL ,
    @SUELDOPERIODO decimal(18,2)            =0,
    @SALARIOMINIMOMES decimal(18,2)         =0,
    @VALOR_MOV decimal(18,2)                =0,
    @AUXTRANSPORTEPERIODO decimal(18,2)     =0,
    @TOTALDEVENGADOPERIODO decimal(18,2)    =0,
    @DIASPERIODO INT                   =0,
    @NUMDIASNOVEDADES_SUELDO INT       =0,
    @NUMDIASNOVEDADES_AUXTRANSPORTE INT=0,
    @PERIODO INT                            =0,
    @ANIOPERIODO INT                        =0,
    @MESPERIODO INT                         =0,
    @FECHAULTIMOPERIODO DATE                =NULL,
    @FECHAULTVACACIONES DATE                =NULL,
    @FECHAINICIOPERIODO DATE                =NULL,
    @NUMEROCONTRATO VARCHAR(50)                ='',
    @FORMULA NVARCHAR(250)='',
    @SINJUSTACAUSA_CONPRESTACIONES  INT =0;

    DECLARE @CODIGOEMP varchar(15), @SALARIO decimal(18,2),@APLICASUBTRAN BIT, @SUBSIDIOTRANSPORTE decimal(18,2), 
	@POR_PENSIONES real, @POR_PENSIONEMPLEADO real,@POR_SALUD real, @POR_SALUDEMPLEADO real,
	@POR_CAJA real,@POR_CESANTIAS real,@POR_PRIMA real,@INT_CESANTIAS real, @POR_VACACIONES real;

    DECLARE @VALOR_AFP_EMPLEADOR decimal(18,2)=0,
        @VALOR_AFP_EMPLEADO decimal(18,2)=0,
        @VALOR_SUBSIDIOTRANSPORTE decimal(18,2)=0,
        @VALOR_EPS_EMPLEADOR decimal(18,2)=0,
	    @VALOR_EPS_EMPLEADO decimal(18,2)=0,
        @VALOR_ARP decimal(18,2)=0,@VALOR_CCF decimal(18,2)=0;

    SET @MENSAJE=''

    IF @IDHOJAVIDA>0
        BEGIN 
           
            --Definir periodo
            IF DATEPART(DAY FROM @FECHARETIRO) > 15 
                BEGIN
                    --Inicializar periodo en dia 30
                    SET @PERIODO=cast(CONVERT(char(6), @FECHARETIRO,112)+'30' as integer);
                    SET @FECHAINICIOPERIODO=cast(CONVERT(char(6), @FECHARETIRO,112)+'16' as DATE);
                END
            ELSE
                BEGIN
                    --Inicializar periodo en dia 15
                    SET @PERIODO=cast(CONVERT(char(6), @FECHARETIRO,112)+'15' as integer);
                    SET @FECHAINICIOPERIODO=cast(CONVERT(char(6), @FECHARETIRO,112)+'01' as DATE);
                END

            SET @PERIODO=cast(CONVERT(char(6), @FECHARETIRO,112)+'30' as integer);
            SET @FECHAINICIOPERIODO=cast(CONVERT(char(6), @FECHARETIRO,112)+'01' as DATE);

             --Validar si ya xiste la liquidacion
            IF EXISTS( SELECT IDLIQUIDACIONDEFINITIVA
                    FROM TH_LIQUIDACIONDEFINITIVA
                    WHERE IDHOJAVIDA=@IDHOJAVIDA
                    AND FECHARETIRO=@FECHARETIRO
                    AND CONTABILIZADO=0)
                BEGIN
                    
                    SELECT @IDNOMINALIQC=IDNOMINALIQC 
                    FROM TH_LIQUIDACIONDEFINITIVA
                    WHERE IDHOJAVIDA=@IDHOJAVIDA
                    AND FECHARETIRO=@FECHARETIRO
                    AND CONTABILIZADO=0;

                    IF(@IDNOMINALIQC>0)
                        BEGIN
                            --Borrar registros anteriores
                            DELETE FROM TH_NOMINALIQD WHERE IDHOJAVIDA=@IDHOJAVIDA AND IDNOMINALIQC=@IDNOMINALIQC;
                            DELETE FROM TH_LIQUIDACIONCESANTIASD WHERE IDHOJAVIDA=@IDHOJAVIDA AND IDLIQUIDACIONCESANTIASC=@IDNOMINALIQC;
                            DELETE FROM TH_LIQUIDACIONINTCESANTIASD WHERE IDHOJAVIDA=@IDHOJAVIDA AND IDLIQUIDACIONINTCESANTIASC=@IDNOMINALIQC;
                            DELETE FROM TH_LIQUIDACIONVACACIONES WHERE IDHOJAVIDA=@IDHOJAVIDA AND FECHA_FINAL=@FECHARETIRO;
                            DELETE FROM TH_LIQUIDACIONPRIMAD WHERE IDHOJAVIDA=@IDHOJAVIDA AND IDLIQUIDACIONPRIMAC=@IDNOMINALIQC;
                            DELETE FROM TH_LIQUIDACIONDEFINITIVA WHERE IDHOJAVIDA=@IDHOJAVIDA AND FECHARETIRO=@FECHARETIRO;
                            DELETE FROM TH_NOMINALIQC WHERE IDNOMINALIQC=@IDNOMINALIQC;
                        END
                END 
            -- Extraer año del periodo
            SET @ANIOPERIODO=DATEPART(YEAR FROM @FECHARETIRO);
            SET @MESPERIODO=DATEPART(MONTH FROM @FECHARETIRO);
            --Traer datos de Empleado
            /* SELECT @CODIGOEMP=HV.CODIGO,@IDCONTRATOHV=CHV.IDCONTRATOHV,@SALARIO=(PA.SALARIOMINIMO*CHV.PORCENTAJESALARIOBASE),@APLICASUBTRAN=CHV.SUBSIDIOTRANSPORTE, 
                @SUBSIDIOTRANSPORTE=IIF(CHV.SUBSIDIOTRANSPORTE=1,PA.SUBSIDIOTRANSPORTE,0), @FECHAINICIOCONTRATO=CHV.FECHAINICIO,@FECHAFINCONTRATO=FECHAVENCIMIENTO,@NUMEROCONTRATO=CHV.NUMEROCONTRATO,
                @POR_PENSIONES=PA.POR_PENSIONES,@POR_PENSIONEMPLEADO=PA.POR_PENSIONEMPLEADO,@POR_SALUD=PA.POR_SALUD,@POR_SALUDEMPLEADO=PA.POR_SALUDEMPLEADO,@POR_CAJA=PA.POR_CAJA,
                @POR_CESANTIAS=PA.POR_CESANTIAS,@POR_PRIMA=PA.POR_PRIMA,@INT_CESANTIAS=PA.INT_CESANTIAS,@POR_VACACIONES=PA.POR_VACACIONES,@SALARIOMINIMOMES=PA.SALARIOMINIMO
                    FROM dbo.TH_HV HV
                    INNER JOIN dbo.TH_CONTRATOHV CHV ON CHV.IDHOJAVIDA=HV.IDHOJAVIDA AND CHV.ESTADO=1
                    JOIN dbo.TH_PARAMETROANUAL PA ON PA.ANIO=YEAR(@FECHARETIRO)
                    --INNER JOIN dbo.TH_PARAMETROANUAL PA ON PA.IDPARAMETROANUAL=CHV.IDPARAMETROANUAL
                WHERE HV.ESTADOHV=1 AND HV.IDHOJAVIDA=@IDHOJAVIDA */
            SELECT @CODIGOEMP=HV.CODIGO,@IDCONTRATOHV=CHV.IDCONTRATOHV,@SALARIO=CHV.SALARIO,@APLICASUBTRAN=CHV.SUBSIDIOTRANSPORTE, 
                @SUBSIDIOTRANSPORTE=IIF(CHV.SUBSIDIOTRANSPORTE=1,PA.SUBSIDIOTRANSPORTE,0), @FECHAINICIOCONTRATO=CHV.FECHAINICIO,@FECHAFINCONTRATO=FECHAVENCIMIENTO,@NUMEROCONTRATO=CHV.NUMEROCONTRATO,
                @POR_PENSIONES=PA.POR_PENSIONES,@POR_PENSIONEMPLEADO=PA.POR_PENSIONEMPLEADO,@POR_SALUD=PA.POR_SALUD,@POR_SALUDEMPLEADO=PA.POR_SALUDEMPLEADO,@POR_CAJA=PA.POR_CAJA,
                @POR_CESANTIAS=PA.POR_CESANTIAS,@POR_PRIMA=PA.POR_PRIMA,@INT_CESANTIAS=PA.INT_CESANTIAS,@POR_VACACIONES=PA.POR_VACACIONES,@SALARIOMINIMOMES=PA.SALARIOMINIMO
                    FROM dbo.TH_HV HV
                    INNER JOIN dbo.TH_CONTRATOHV CHV ON CHV.IDHOJAVIDA=HV.IDHOJAVIDA AND CHV.ESTADO=1
                    --JOIN dbo.TH_PARAMETROANUAL PA ON PA.ANIO=YEAR(@FECHARETIRO)
                    INNER JOIN dbo.TH_PARAMETROANUAL PA ON PA.ANIO=YEAR(@FECHARETIRO)
                WHERE HV.ESTADOHV=1 AND HV.IDHOJAVIDA=@IDHOJAVIDA;
           
            IF LEN(@CODIGOEMP)>0
                BEGIN
                    --Revisar ultimas vacaciones
                    SELECT @FECHAULTVACACIONES=MAX(D.FECHA_RETORNO) 
                            FROM TH_LIQUIDACIONVACACIONES D
                        WHERE D.IDHOJAVIDA=@IDHOJAVIDA;

                    --Traer fecha de ultima liquidacion
                    SELECT @FECHAULTIMOPERIODO=MAX(C.FECHALIQUIDACION) 
                        FROM TH_NOMINALIQD D
                        INNER JOIN TH_NOMINALIQC C ON C.IDNOMINALIQC=D.IDNOMINALIQC
                    WHERE D.IDHOJAVIDA=@IDHOJAVIDA and C.MOD_ORIGEN IN ('LIQNOM','LIQDEF') and C.ESTADO <>'P';
                    --Definir rango del periodo
                    IF @FECHAULTIMOPERIODO IS NULL
                        BEGIN                            

                            IF @FECHAULTIMOPERIODO IS NOT NULL AND @FECHAULTIMOPERIODO > @FECHAINICIOPERIODO
                                BEGIN
                                    SET  @FECHAULTIMOPERIODO=@FECHAULTIMOPERIODO;
                                END
                            ELSE
                                BEGIN
                                    SET  @FECHAULTIMOPERIODO=@FECHAINICIOPERIODO;
                                END
                        END
                    ELSE
                        BEGIN

                            IF @FECHAULTVACACIONES IS NOT NULL AND @FECHAULTVACACIONES > @FECHAULTIMOPERIODO
                                BEGIN                                   
                                    SET  @FECHAULTIMOPERIODO=@FECHAULTVACACIONES;
                                END
                            ELSE
                                BEGIN
                                    IF(DAY(@FECHAULTIMOPERIODO)=30 OR (@FECHAULTIMOPERIODO=EOMONTH(@FECHAULTIMOPERIODO) AND MONTH(@FECHAULTIMOPERIODO)=2))
                                        BEGIN
                                            SET  @FECHAULTIMOPERIODO=DATEADD(day, 1, EOMONTH(@FECHAULTIMOPERIODO));
                                        END
                                    ELSE
                                        BEGIN 
                                            SET  @FECHAULTIMOPERIODO=DATEADD(day, 1, @FECHAULTIMOPERIODO);                 
                                        END  
                                END
                            
                        END

                    --Crear registro cabecera
                    INSERT INTO dbo.TH_NOMINALIQC (PERIODO, FECHALIQUIDACION, FECHAMOVIMIENTO, MOD_ORIGEN, ESTADO, DESCRIPCION, EMPLEADOS_LIQUIDADOS, OBSERVACIONESLIQUIDACION, USUARIOTRCR,FECHATRCR, USUARIOTRED, FECHATRED)
                    VALUES (@PERIODO,@FECHARETIRO,GETDATE(),'LIQDEF','P','LIQUIDACION DEFINITIVA COD.'+@CODIGOEMP,1,'LIQUIDACION DEF','ESPO',GETDATE(),'ESPO',GETDATE());
                    
                    SET @IDNOMINALIQC= SCOPE_IDENTITY();
                    --Si el dia de liquidacion es igual al dia de  ultimo periodo , solo calcular prestaciones
                     
                    IF @FECHAULTIMOPERIODO >@FECHARETIRO
                    BEGIN
                        SET @SUELDOPERIODO =0;
                    END 
                    ELSE
                    BEGIN 
                        -- Calcular dias periodo                    
                        SET @DIASPERIODO=DATEDIFF(DAY, @FECHAULTIMOPERIODO, DATEADD(day, 1, @FECHARETIRO) );    
                       
                        --Traer dias de novedades que afectan salario
                        
                        EXEC @NUMDIASNOVEDADES_SUELDO=sp_TH_DIASNOVEDADESPERSONAL 
                                                        @IDHOJAVIDA=@IDHOJAVIDA,
                                                        @FECHAINICIO=@FECHAULTIMOPERIODO,
                                                        @FECHAFIN=@FECHARETIRO,
                                                        @OPCION='AFECTA_SALARIO',
                                                        @IDNOMINALIQC=@IDNOMINALIQC;

                        --Si hay novedades  restar dias
                        IF @NUMDIASNOVEDADES_SUELDO>0 AND @DIASPERIODO>0
                        BEGIN
                            SET @DIASPERIODO=@DIASPERIODO-@NUMDIASNOVEDADES_SUELDO;
                        END
                        --PRINT 'DIAS PERIODO:'+STR(@DIASPERIODO)
                        --Calcular valores del periodo
                        SET @SUELDOPERIODO = (@SALARIO/30)*@DIASPERIODO;

                        SET @VALOR_AFP_EMPLEADOR = @SUELDOPERIODO*(@POR_PENSIONES)/100;
                        SET @VALOR_AFP_EMPLEADO = @SUELDOPERIODO*(@POR_PENSIONEMPLEADO)/100;
                        SET @VALOR_EPS_EMPLEADOR = (@SUELDOPERIODO*@POR_SALUD)/100;
                        SET @VALOR_EPS_EMPLEADO = (@SUELDOPERIODO*@POR_SALUDEMPLEADO)/100;

                        --Verificar si hay novedad de aumento transitorio de salario
                        DECLARE @VALORNOV decimal(18,2)=0,@TOTALDIASNOVEDAD INT =0,@SUELDOPERIODOADD decimal(18,2)=0;
                        SELECT @VALORNOV=VALOR,
                            @TOTALDIASNOVEDAD=IIF(FECHAFIN < @FECHARETIRO, DATEDIFF(day,IIF(FECHAINICIO<@FECHAULTIMOPERIODO,@FECHAULTIMOPERIODO,FECHAINICIO) ,DATEADD(day, 1, FECHAFIN)),
                            DATEDIFF(day,IIF(FECHAINICIO<@FECHAULTIMOPERIODO,@FECHAULTIMOPERIODO,FECHAINICIO) ,DATEADD(day, 1, @FECHARETIRO)))              
                            FROM TH_NOVEDAD
                            INNER JOIN TH_DM_SUBTIPONOVEDAD ON TH_DM_SUBTIPONOVEDAD.IDSUBTIPONOVEDAD=TH_NOVEDAD.IDSUBTIPONOVEDAD
                            WHERE IDHOJAVIDA=@IDHOJAVIDA AND TH_DM_SUBTIPONOVEDAD.IDSUBTIPONOVEDAD=8   
                            AND @FECHAULTIMOPERIODO < FECHAFIN
                            AND @FECHARETIRO > FECHAINICIO;
                        
                        IF @TOTALDIASNOVEDAD>0 AND @VALORNOV>0
                            BEGIN
                                SET @SUELDOPERIODOADD=(@VALORNOV/30)*@TOTALDIASNOVEDAD;

                                --Recalcular valores periodo
                                SET @SUELDOPERIODO = @SUELDOPERIODO+@SUELDOPERIODOADD;
                                SET @VALOR_AFP_EMPLEADOR    =   @SUELDOPERIODO*(@POR_PENSIONES)/100;
                                SET @VALOR_AFP_EMPLEADO     =   @SUELDOPERIODO*(@POR_PENSIONEMPLEADO)/100;
                                SET @VALOR_EPS_EMPLEADOR    =   (@SUELDOPERIODO*@POR_SALUD)/100;
                                SET @VALOR_EPS_EMPLEADO     =   (@SUELDOPERIODO*@POR_SALUDEMPLEADO)/100;

                            END 
                    END

                    IF @IDNOMINALIQC>0
                        BEGIN
                            --Guardar Registro de liquidacion definitiva
                            INSERT INTO dbo.TH_LIQUIDACIONDEFINITIVA (IDHOJAVIDA,IDCONTRATOHV,FECHALIQUIDACION,FECHARETIRO,TOTALPAGADO,TOTALDEVENGADO,TOTALDEDUCIDO,OBSERVACION,CONTABILIZADO,IDNOMINALIQC,USUARIOTRCR,FECHATRCR, USUARIOTRED, FECHATRED)
                            VALUES (@IDHOJAVIDA,@IDCONTRATOHV,GETDATE(),@FECHARETIRO,0,0,0,'LIQUIDACION DEFINITIVA',0,@IDNOMINALIQC, 'ESPO',GETDATE(),'ESPO',GETDATE());
                            --Guardar Movimientos
                            DECLARE @IDCONCEPTO INT ;
                            DECLARE @CODCONCEPTO VARCHAR(20) ;

                            --Sueldo  Cod 29
                            SET @IDCONCEPTO =29;
                            SET @CODCONCEPTO ='DV-SUELDOB';
                            SET @FORMULA='F ULTPERIODO:'+CONVERT(varchar,@FECHAULTIMOPERIODO,23)+' FFIN:'+CONVERT(varchar,@FECHARETIRO,23)+' SALARIO :'+STR(@SALARIO)+' * SUELDO ADD: '+STR(@SUELDOPERIODOADD)+' DIAS: '+STR(@DIASPERIODO)+' ';
                            --LIQ D 
                            IF @SUELDOPERIODO >0
                            BEGIN
                                INSERT INTO dbo.TH_NOMINALIQD (IDNOMINALIQC,IDHOJAVIDA,IDCONCEPTO,CODIGOCONCEPTO,VALOR,FECHAMOVIMIENTO,FECHA_LIQUIDACION,USUARIO_PRELIQUIDO,CERRADO,CUENTADEBITO,CUENTACREDITO,CENTROCOSTO,FECHAPRELIQUIDACION,N_CONTRATO,FORMULAPLICAR,DIAS)
                                VALUES (@IDNOMINALIQC,@IDHOJAVIDA,@IDCONCEPTO,@CODCONCEPTO,@SUELDOPERIODO,GETDATE(),GETDATE(),'ESPO',0,'510101','250501','',GETDATE(),@NUMEROCONTRATO,@FORMULA,@DIASPERIODO);
                            END

                            --Auxilio Transporte  Cod 28
                            IF @SUELDOPERIODO >0 AND @APLICASUBTRAN=1
                                BEGIN
                                    SET @IDCONCEPTO  =28;
                                    SET @CODCONCEPTO  ='DV-SUBTRAN';

                                    --Calcular dias a liquidar 
                                    --SET @DIASPERIODO=DATEDIFF(DAY, @FECHAULTIMOPERIODO, DATEADD(day, 1, @FECHARETIRO) ) ;
                                    --Traer dias de novedades que afectan auxilio
                                    /* EXEC @NUMDIASNOVEDADES_AUXTRANSPORTE=sp_TH_DIASNOVEDADESPERSONAL 
                                                                            @IDHOJAVIDA=@IDHOJAVIDA,
                                                                            @FECHAINICIO=@FECHAULTIMOPERIODO,
                                                                            @FECHAFIN=@FECHARETIRO,
                                                                            @OPCION='AFECTA_AUXTRANSPORTE',
                                                                            @IDNOMINALIQC=@IDNOMINALIQC; */
                                    
                                    /* IF @NUMDIASNOVEDADES_AUXTRANSPORTE>0
                                        BEGIN
                                            SET @DIASPERIODO=@DIASPERIODO-@NUMDIASNOVEDADES_AUXTRANSPORTE;
                                        END */

                                    SET @AUXTRANSPORTEPERIODO = (@SUBSIDIOTRANSPORTE/30)*@DIASPERIODO;
                                    SET @TOTALDEVENGADOPERIODO = @SUELDOPERIODO+@AUXTRANSPORTEPERIODO;

                                    --LIQ D 
                                    INSERT INTO dbo.TH_NOMINALIQD (IDNOMINALIQC,IDHOJAVIDA,IDCONCEPTO,CODIGOCONCEPTO,VALOR,FECHAMOVIMIENTO,FECHA_LIQUIDACION,USUARIO_PRELIQUIDO,CERRADO,CUENTADEBITO,CUENTACREDITO,CENTROCOSTO,FECHAPRELIQUIDACION,N_CONTRATO,DIAS)
                                    VALUES (@IDNOMINALIQC,@IDHOJAVIDA,@IDCONCEPTO,@CODCONCEPTO,@AUXTRANSPORTEPERIODO,GETDATE(),GETDATE(),'ESPO',0,'510123','250501','',GETDATE(),@NUMEROCONTRATO,@DIASPERIODO);
                                END

                            /* --Aportes Pension Empleado   ---Se calcula en el paso de contabilizacion
                                SET @IDCONCEPTO  =4;
                                SET @CODCONCEPTO  ='DD-APPENSI';
                                SET @FORMULA='FINI:'+CONVERT(varchar,@FECHAULTIMOPERIODO,23)+' FFIN:'+CONVERT(varchar,@FECHARETIRO,23)+' SUELDO :'+STR(@SUELDOPERIODO)+' * PORC: '+STR(@POR_PENSIONEMPLEADO)+' DIAS: '+STR(@DIASPERIODO)+' ';

                                --LIQ D 
                                IF @VALOR_AFP_EMPLEADO>0
                                BEGIN
                                    INSERT INTO dbo.TH_NOMINALIQD (IDNOMINALIQC,IDHOJAVIDA,IDCONCEPTO,CODIGOCONCEPTO,VALOR,FECHAMOVIMIENTO,FECHA_LIQUIDACION,USUARIO_PRELIQUIDO,CERRADO,CUENTADEBITO,CUENTACREDITO,CENTROCOSTO,FECHAPRELIQUIDACION,N_CONTRATO,FORMULAPLICAR,DIAS)
                                    VALUES (@IDNOMINALIQC,@IDHOJAVIDA,@IDCONCEPTO,@CODCONCEPTO,@VALOR_AFP_EMPLEADO,GETDATE(),GETDATE(),'ESPO',0,'250501','242518','',GETDATE(),@NUMEROCONTRATO,@FORMULA,@DIASPERIODO) ;
                                END 
                            --Salud
                                SET @IDCONCEPTO  =5;
                                SET @CODCONCEPTO  ='DD-APSALUD';
                                SET @FORMULA='FINI:'+CONVERT(varchar,@FECHAULTIMOPERIODO,23)+' FFIN:'+CONVERT(varchar,@FECHARETIRO,23)+' SUELDO :'+STR(@SUELDOPERIODO)+' * PORC: '+STR(@POR_SALUDEMPLEADO)+' DIAS: '+STR(@DIASPERIODO)+' ';

                                --LIQ D 
                                IF @VALOR_EPS_EMPLEADO>0
                                BEGIN
                                    INSERT INTO dbo.TH_NOMINALIQD (IDNOMINALIQC,IDHOJAVIDA,IDCONCEPTO,CODIGOCONCEPTO,VALOR,FECHAMOVIMIENTO,FECHA_LIQUIDACION,USUARIO_PRELIQUIDO,CERRADO,CUENTADEBITO,CUENTACREDITO,CENTROCOSTO,FECHAPRELIQUIDACION,N_CONTRATO,FORMULAPLICAR,DIAS)
                                    VALUES (@IDNOMINALIQC,@IDHOJAVIDA,@IDCONCEPTO,@CODCONCEPTO,@VALOR_EPS_EMPLEADO,GETDATE(),GETDATE(),'ESPO',0,'250501','242519','',GETDATE(),@NUMEROCONTRATO,@FORMULA,@DIASPERIODO) ;
                                END */

                            --PG-CESANTI
                                EXEC sp_TH_LIQCESANTIAS_DET @IDNOMINALIQC,@ANIOPERIODO ,@USERNAME  ,@IDHOJAVIDA,@FECHARETIRO;
                            --PG-INTCESA
                                EXEC sp_TH_LIQINTCESANTIAS_DET @IDNOMINALIQC,@ANIOPERIODO ,@USERNAME ,@IDHOJAVIDA,@FECHARETIRO;
                            --PG-VACACIO
                                EXEC sp_TH_LIQVACACIONES_HV @IDNOMINALIQC,@FECHARETIRO ,@USERNAME ,  @IDHOJAVIDA;
                            --PG-PRIMASE
                                --Traer ultima fecha periodo de prima
                                EXEC sp_TH_LIQPRIMA_HV @IDNOMINALIQC,@IDHOJAVIDA,@FECHARETIRO,@USERNAME;
                            --Descuentos autorizados nomina
                                EXEC dbo.sp_TH_NOVEDADESDESCUENTO_HV @FECHAULTIMOPERIODO,@FECHARETIRO,@IDHOJAVIDA,@IDNOMINALIQC;

                            --Solidaridad
                            IF (@SUELDOPERIODO/@SALARIOMINIMOMES) >4.00
                                BEGIN
                                    SET @IDCONCEPTO  =3;
                                    SET @CODCONCEPTO  ='DD-APFSOLI';
                                    SET @VALOR_MOV=@SUELDOPERIODO*0.01;
                                    --LIQ D 
                                    INSERT INTO dbo.TH_NOMINALIQD (IDNOMINALIQC,IDHOJAVIDA,IDCONCEPTO,CODIGOCONCEPTO,VALOR,FECHAMOVIMIENTO,FECHA_LIQUIDACION,USUARIO_PRELIQUIDO,CERRADO,CUENTADEBITO,CUENTACREDITO,CENTROCOSTO,FECHAPRELIQUIDACION,DOCUMENTO)
                                    VALUES (@IDNOMINALIQC,@IDHOJAVIDA,@IDCONCEPTO,@CODCONCEPTO,@VALOR_MOV,GETDATE(),GETDATE(),'ESPO',0,'250501','242518','123',GETDATE(),STR(@IDNOMINALIQC));
                                    
                                END
                            
                            IF @SINJUSTACAUSA=1
                                BEGIN
                                    DECLARE @VALOR_CES decimal(18,2)   =0 
                                    DECLARE @VALOR_INTCES decimal(18,2) =0
                                    DECLARE @VALOR_VACAS decimal(18,2) =0
                                    DECLARE @VALOR_PRIMA decimal(18,2) =0
                                    DECLARE @TOTALINDEMNIZACION decimal(18,2) =0
	                                DECLARE @POR_INTCESANTIAS decimal(18,2)	=0.12

                                    --Calcular valores desde fecha retiro hasta fecha fin contrato
                                    
                                    SET @DIASPERIODO=dbo.Days360( DATEADD(day, 1, @FECHARETIRO) , DATEADD(day, 1, @FECHAFINCONTRATO) )

                                    /* PRINT @FECHARETIRO
                                    PRINT @FECHAFINCONTRATO
                                    PRINT 'DIAS JUSTA CAUSA'+STR(@DIASPERIODO)  */

                                    SET @SUELDOPERIODO = (@SALARIO/30)*@DIASPERIODO
                                    --PRINT 'SUELDO:'+STR(@SUELDOPERIODO)
                                    SET @AUXTRANSPORTEPERIODO = (@SUBSIDIOTRANSPORTE/30)*@DIASPERIODO
                                    SET @TOTALDEVENGADOPERIODO = @SALARIO+@SUBSIDIOTRANSPORTE
                                    --Cesantias
				                    SET @VALOR_CES= (@TOTALDEVENGADOPERIODO*@DIASPERIODO)/360
                                    --Int Cesantas
                                    SET @VALOR_INTCES=(@VALOR_CES*@DIASPERIODO*@POR_INTCESANTIAS)/360
                                    --Vacaciones
                                    SET @VALOR_VACAS=(@TOTALDEVENGADOPERIODO*@DIASPERIODO)/720
                                    --PRIMA
                                    SET @VALOR_PRIMA=(@TOTALDEVENGADOPERIODO*@DIASPERIODO)/360

                                    /* PRINT 'DIAS:'+STR(@DIASPERIODO)
                                    PRINT 'SUELDO:'+STR(@AUXTRANSPORTEPERIODO)
                                    PRINT 'CES:'+STR(@VALOR_CES)
                                    PRINT 'INT CES:'+STR(@VALOR_INTCES)
                                    PRINT 'VACAS:'+STR(@VALOR_VACAS)
                                    PRINT 'PRIMA:'+STR(@VALOR_PRIMA) */ 
                                    IF @SINJUSTACAUSA_CONPRESTACIONES=1
                                        BEGIN
                                            SET @TOTALINDEMNIZACION=@SUELDOPERIODO+@AUXTRANSPORTEPERIODO+@VALOR_CES+@VALOR_INTCES+@VALOR_VACAS+@VALOR_PRIMA
                                        END
                                    ELSE
                                        BEGIN
                                            SET @TOTALINDEMNIZACION=@SUELDOPERIODO
                                        END

                                    IF @TOTALINDEMNIZACION>0
                                        BEGIN 
                                            SET @IDCONCEPTO  =59
                                            SET @CODCONCEPTO  ='PG-INDEMNI'
                                            SET @FORMULA='FECHA FIN CONTRATO:'+CONVERT(varchar,@FECHAFINCONTRATO,23)+' FFIN:'+CONVERT(varchar,@FECHARETIRO,23)+', SUELDO :'+STR(@SUELDOPERIODO)+', AUX TRANS: '+STR(@AUXTRANSPORTEPERIODO)+', CESANTIAS: '+STR(@VALOR_CES)+', INTCES: '+STR(@VALOR_INTCES)+', VACAS: '+STR(@VALOR_VACAS)+', PRIMA: '+STR(@VALOR_PRIMA)+', DIAS: '+STR(@DIASPERIODO)+' '
                                            --LIQ D 
                                            INSERT INTO dbo.TH_NOMINALIQD (IDNOMINALIQC,IDHOJAVIDA,IDCONCEPTO,CODIGOCONCEPTO,VALOR,FECHAMOVIMIENTO,FECHA_LIQUIDACION,USUARIO_PRELIQUIDO,CERRADO,CUENTADEBITO,CUENTACREDITO,CENTROCOSTO,FECHAPRELIQUIDACION,N_CONTRATO,FORMULAPLICAR,DIAS)
                                            VALUES (@IDNOMINALIQC,@IDHOJAVIDA,@IDCONCEPTO,@CODCONCEPTO,@TOTALINDEMNIZACION,GETDATE(),GETDATE(),'ESPO',0,'510560','283005','',GETDATE(),@NUMEROCONTRATO,@FORMULA,@DIASPERIODO) 
                                        END 
                                END

                        END

                END
                ELSE
                    BEGIN
                        SET @MENSAJE='Revise el registro del empleado si esta activo y tiene un contrato vigente'
                        SET @ERROR=1
                        RETURN
                    END
        END

    IF @IDNOMINALIQC > 0
        BEGIN            
            SET @MENSAJE='Registro agregado correctamente'
        END
    ELSE 
        BEGIN
            SET @MENSAJE='Registro ya existe' 
            SET @ERROR=2
        END

END
GO