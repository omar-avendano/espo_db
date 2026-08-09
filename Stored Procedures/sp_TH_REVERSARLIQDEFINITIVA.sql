USE [ESPO]
GO
/****** Object:  StoredProcedure [dbo].[sp_TH_REVERSARLIQDEFINITIVA]    Script Date: 8/8/2025 9:31:43 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[sp_TH_REVERSARLIQDEFINITIVA]
@IDNOMINALIQC INT,
@USERNAME VARCHAR(60) ,
@MENSAJE varchar(150) OUTPUT
AS
BEGIN
SET NOCOUNT ON

    SET @MENSAJE='';
    DECLARE @IDMOVGC INT =0;
    DECLARE @NUMTRANSACCION INT =0;

    IF @IDNOMINALIQC>0
    BEGIN 
        --Validar si ya existe la contabilizacion
        IF EXISTS( SELECT TOP 1 1
                FROM TH_NOMINAMOVCNT
                WHERE IDNOMINALIQC=@IDNOMINALIQC)
            BEGIN
                
                --Borrar registros de contabilizacion
                DELETE FROM TH_NOMINAMOVCNT WHERE IDNOMINALIQC=@IDNOMINALIQC;

                --Borrar registros de  pagos y asientos 
                SELECT 
                    @IDMOVGC=IDMOVGC ,@NUMTRANSACCION=NUMDOCUME
                FROM GC_MOV_C
                WHERE NUMDOCUMEREL=CAST(@IDNOMINALIQC AS VARCHAR(30))
                AND DESCRIPCION like 'CAUSACION PAGO LIQUIDACION CONTRATO'
                AND CONTABILIZADO=1;

                IF(@IDMOVGC>0)
                BEGIN
                    --1. Borrar Asientos
                    IF @NUMTRANSACCION>0 DELETE FROM GC_ASIENTO WHERE TPDOC = 'TRA' AND NUMDOC = @NUMTRANSACCION;
                    --Borrar registros de pago
                    DELETE FROM GC_MOV_D WHERE IDMOVGC=@IDMOVGC; --Detalles
                    DELETE from GC_MOV_C where IDMOVGC=@IDMOVGC; --Cabecera
                    
                    SET @MENSAJE='Contabilización y pago borrado correctamente';
                END

                UPDATE TH_NOMINALIQC
                SET ESTADO='L' 
                WHERE IDNOMINALIQC=@IDNOMINALIQC;
                
            END 
        
    END
    ELSE
    BEGIN            
        SET @MENSAJE='No se envio el numero de transacción';
    END

END