USE [ESPO]
GO
/****** Object:  StoredProcedure [dbo].[sp_TH_CONTABILIZAR_NOMINA]    Script Date: 17/11/2025 9:54:53 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[sp_TH_CONTABILIZAR_NOMINA]
@IDNOMINA INT,
@USERNAME VARCHAR(60) 
AS
BEGIN
SET NOCOUNT ON

DECLARE 
        @IDHOJAVIDA INT =0,
        @IDCONTRATOHV INT =0,
        @IDCONCEPTO INT =0,
        @DIAS INT =0,
        @VALOR DECIMAL(10,2) =0,
        @VALORAJUSTERES DECIMAL(10,2) =0,
        @VALORAJUSTEADD DECIMAL(10,2) =0,
        @VALORCONTABILIZAR DECIMAL(10,2) =0,
        @CODTERCERO VARCHAR(15)='',
        @CUENTA VARCHAR(15)='',
        @TIPO VARCHAR(1)='',
        @NOMCUENTADEBITO VARCHAR(15)='',
        @NOMCUENTACREDITO VARCHAR(15)=''
 DECLARE
        @CODIGO VARCHAR(15) ='',
        @PORCENTAJE DECIMAL(10,2) =0,
        @NUMASIENTO INT =0,
        @VALORMOV DECIMAL(10,2),
        @VALORDESEMP DECIMAL(10,2)=0,
        @VALOREXCESOS DECIMAL(10,2)=0,
        @ESTADO CHAR(1)='',
        @EXISTBASE BIT =0

SELECT @ESTADO=ESTADO
FROM TH_NOMINALIQC 
WHERE IDNOMINALIQC=@IDNOMINA

IF LEN(@ESTADO)>0 AND @ESTADO='L'
    BEGIN  
        
        DECLARE CurLiquidaciones CURSOR FOR
        SELECT XXX.IDHOJAVIDA, XXX.CODIGO, XXX.CTA, XXX.TIPO, XXX.TOTAL,XXX.IDCONTRATOHV,XXX.DIAS
        FROM (
            SELECT 
                LIQ.IDHOJAVIDA,HV.CODIGO,LIQ.DIAS,
                CASE 
                    WHEN CHV.CUENTABASE = '7' AND M.CTA_DEBITO_BASE7 <> '' THEN M.CTA_DEBITO_BASE7 
                    ELSE M.CTA_DEBITO 
                END AS CTA, 
                'D' AS TIPO,
                SUM(LIQ.VALOR) AS TOTAL,
                CHV.IDCONTRATOHV
            FROM dbo.TH_NOMINALIQD LIQ
            INNER JOIN dbo.TH_CONTRATOHV CHV ON CHV.IDHOJAVIDA = LIQ.IDHOJAVIDA AND CHV.ESTADO = 1
            INNER JOIN TH_HV HV ON HV.IDHOJAVIDA = CHV.IDHOJAVIDA
            JOIN TH_PR_CONCEPTO C ON C.IDCONCEPTO = LIQ.IDCONCEPTO
            JOIN TH_PR_MODOCONTABLE M ON M.COD_MODOCONTABLE = C.COD_MODOCONTABLE
            WHERE LIQ.IDNOMINALIQC = @IDNOMINA
            --AND HV.IDHOJAVIDA = 174
            --AND M.CTA_DEBITO <> '250501'
            AND (M.CTA_DEBITO <> '250501' OR ( M.CTA_DEBITO = '250501' AND LIQ.CLASIFICACION='EX'))
            GROUP BY LIQ.IDHOJAVIDA,HV.CODIGO,LIQ.DIAS, 
                    CASE 
                        WHEN CHV.CUENTABASE = '7' AND M.CTA_DEBITO_BASE7 <> '' THEN M.CTA_DEBITO_BASE7 
                        ELSE M.CTA_DEBITO 
                    END,
                    CHV.IDCONTRATOHV    
            UNION ALL    
            SELECT 
                LIQ.IDHOJAVIDA,HV.CODIGO,LIQ.DIAS,
                M.CTA_CREDITO AS CTA, 
                'C' AS TIPO,
                SUM(LIQ.VALOR) AS TOTAL,
                CHV.IDCONTRATOHV
            FROM dbo.TH_NOMINALIQD LIQ
            INNER JOIN dbo.TH_CONTRATOHV CHV ON CHV.IDHOJAVIDA = LIQ.IDHOJAVIDA AND CHV.ESTADO = 1
            INNER JOIN TH_HV HV ON HV.IDHOJAVIDA = CHV.IDHOJAVIDA
            JOIN TH_PR_CONCEPTO C ON C.IDCONCEPTO = LIQ.IDCONCEPTO
            JOIN TH_PR_MODOCONTABLE M ON M.COD_MODOCONTABLE = C.COD_MODOCONTABLE
            WHERE LIQ.IDNOMINALIQC = @IDNOMINA
            --AND HV.IDHOJAVIDA = 174
            GROUP BY LIQ.IDHOJAVIDA,HV.CODIGO,LIQ.DIAS, M.CTA_CREDITO,CHV.IDCONTRATOHV
        ) AS XXX
        ORDER BY XXX.CODIGO, XXX.CTA

        OPEN CurLiquidaciones
            FETCH NEXT FROM CurLiquidaciones INTO @IDHOJAVIDA,@CODTERCERO,@CUENTA,@TIPO,@VALOR,@IDCONTRATOHV,@DIAS

            WHILE (@@FETCH_STATUS = 0) 
            BEGIN
                SET @VALORCONTABILIZAR=0;
                SET @VALORAJUSTERES=0;
                SET @VALORAJUSTEADD=0;
                SET @CODIGO='';
                SET @EXISTBASE=0;

                IF EXISTS( SELECT TOP 1 1FROM TH_NOMINA_BASE WHERE IDHOJAVIDA=@IDHOJAVIDA AND IDNOMINALIQC=@IDNOMINA) 
                BEGIN
                    SET @EXISTBASE=1;
                END
                ELSE 
                BEGIN
                    SET @EXISTBASE=0;
                END
                
                --PRINT 'PREV --CUENTA: '+@CUENTA+' VALOR: '+STR(@VALOR)            
                IF (@CUENTA='510307' or @CUENTA='750534') AND @EXISTBASE=1
                    BEGIN 
                        --Traer valor a ajsutar por excesos solo el 4% de empleado de lo de nomina no vacaciones
                        SELECT TOP 1 @VALORAJUSTERES=SUM(VALOR)
                        FROM TH_NOMINALIQD
                        WHERE IDHOJAVIDA=@IDHOJAVIDA AND IDNOMINALIQC =@IDNOMINA AND DIAS=@DIAS
                        AND CUENTADEBITO= '250501' AND CUENTACREDITO='242518' AND CLASIFICACION='' AND IDCONCEPTO<>3;
                        
                        SET @VALORCONTABILIZAR=@VALOR-ISNULL(@VALORAJUSTERES,0);
                        
                    END 
                ELSE IF (@CUENTA='510303' OR @CUENTA='750537') AND @EXISTBASE=1
                    BEGIN 
                        --Traer valor a ajsutar por excesos
                        SELECT TOP 1 @VALORAJUSTERES=SUM(VALOR)
                        FROM TH_NOMINALIQD
                        WHERE IDHOJAVIDA=@IDHOJAVIDA AND IDNOMINALIQC =@IDNOMINA AND DIAS=@DIAS
                        AND CUENTADEBITO= '250501' AND CUENTACREDITO='242519';
                        
                        SET @VALORCONTABILIZAR=@VALOR-ISNULL(@VALORAJUSTERES,0);
                        
                    END 
                ELSE IF @CUENTA='250501' AND @EXISTBASE=1
                    BEGIN 
                        --Traer valor a ajsutar por excesos
                        SELECT @VALORAJUSTERES=SUM(VALOR)
                        FROM TH_NOMINALIQD
                        WHERE IDHOJAVIDA=@IDHOJAVIDA AND IDNOMINALIQC =@IDNOMINA AND DIAS=@DIAS
                        AND ( (CUENTACREDITO ='242518' AND CUENTADEBITO = '250501' )
                            OR 	(CUENTACREDITO IN ('242541','242519','23360101','242535')  )
                        );
                        
                        SELECT @VALORAJUSTEADD=SUM(VALOR)
                        FROM TH_NOMINALIQD
                        WHERE IDHOJAVIDA=@IDHOJAVIDA AND IDNOMINALIQC =@IDNOMINA AND DIAS=@DIAS
                        AND (CUENTACREDITO ='242520' AND CLASIFICACION = 'EX');
                        
                        SET @VALORCONTABILIZAR=@VALOR-ISNULL(@VALORAJUSTERES,0)+ISNULL(@VALORAJUSTEADD,0);
                        
                    END 
                ELSE
                    BEGIN
                        SET @VALORCONTABILIZAR=@VALOR;
                    END 
                
                --PRINT 'POST --CUENTA: '+@CUENTA+' VALOR: '+STR(@VALORCONTABILIZAR)
                IF @TIPO ='D'
                    BEGIN
                        --PRINT 'D , CONTRATO:'+STR(@IDCONTRATOHV)
                        DECLARE CurCentroCosto CURSOR FOR
                        SELECT CC.CODIGO,CENTRO.PORCENTAJE
                        FROM TH_CONTRATOHV_CENTROCOSTO CENTRO
                        JOIN GC_CENTROCOSTO CC ON CC.IDCENTROCOSTO=CENTRO.IDCENTROCOSTO
                        WHERE CENTRO.IDCONTRATOHV=@IDCONTRATOHV
                        
                        OPEN CurCentroCosto
                        FETCH NEXT FROM CurCentroCosto INTO @CODIGO,@PORCENTAJE
                        WHILE (@@FETCH_STATUS = 0) 
                        BEGIN
                            SET @NUMASIENTO=@NUMASIENTO+1;
                            SET @VALORMOV=(@VALORCONTABILIZAR*@PORCENTAJE)/100;
                            --PRINT 'VALOR MOV:'+STR(@VALORMOV)
                            --MOV DEBITO DISTRIBUIDO EN CENTROS DE COSTO                                 
                            INSERT INTO TH_NOMINAMOVCNT (IDNOMINALIQC,NUMASIENTO,COD_TERCERO,CENTRO,TIPO_ASIENTO,COD_CUENTA,DESCRIPCION,NATURALEZA,BASE,VALOR,CEN_SUB,FECHA_ENV,FECHA_LIQ,CONTABILIZADO,MOD_ORIGEN,FECHATRCR,USUARIOTRCR,FECHATRED,USUARIOTRED)
                            VALUES (@IDNOMINA,@NUMASIENTO,@CODTERCERO,@CODIGO,'N',@CUENTA,@NOMCUENTACREDITO,@TIPO,@VALOR,@VALORMOV,@CODIGO,GETDATE(),GETDATE(),0,'LIQNOM',GETDATE(),@USERNAME,GETDATE(),@USERNAME);

                            FETCH NEXT FROM CurCentroCosto INTO @CODIGO,@PORCENTAJE
                        END 

                        CLOSE CurCentroCosto
                        DEALLOCATE CurCentroCosto

                    END 
                ELSE
                BEGIN

                    SET @NUMASIENTO=@NUMASIENTO+1;

                    INSERT INTO TH_NOMINAMOVCNT (IDNOMINALIQC,NUMASIENTO,COD_TERCERO,CENTRO,TIPO_ASIENTO,COD_CUENTA,DESCRIPCION,NATURALEZA,BASE,VALOR,CEN_SUB,FECHA_ENV,FECHA_LIQ,CONTABILIZADO,MOD_ORIGEN,FECHATRCR,USUARIOTRCR,FECHATRED,USUARIOTRED)
                    VALUES (@IDNOMINA,@NUMASIENTO,@CODTERCERO,@CODIGO,'N',@CUENTA,@NOMCUENTACREDITO,@TIPO,@VALOR,@VALORCONTABILIZAR,@CODIGO,GETDATE(),GETDATE(),0,'LIQNOM',GETDATE(),@USERNAME,GETDATE(),@USERNAME);
                END
            
                FETCH NEXT FROM CurLiquidaciones INTO @IDHOJAVIDA,@CODTERCERO,@CUENTA,@TIPO,@VALOR,@IDCONTRATOHV,@DIAS
            END 

            CLOSE CurLiquidaciones;
            DEALLOCATE CurLiquidaciones;
            --Cambiar de estado Nomina
            UPDATE TH_NOMINALIQC 
                SET ESTADO='C' 
            WHERE IDNOMINALIQC=@IDNOMINA;
    END

END