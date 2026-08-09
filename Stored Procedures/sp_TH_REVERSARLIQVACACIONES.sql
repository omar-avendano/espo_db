USE [ESPO]
GO
/****** Object:  StoredProcedure [dbo].[sp_TH_REVERSARLIQVACACIONES]    Script Date: 8/8/2025 9:31:43 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[sp_TH_REVERSARLIQVACACIONES]
@IDLIQUIDACION INT,
@USERNAME VARCHAR(60) ,
@MENSAJE varchar(150) OUTPUT
AS
BEGIN
SET NOCOUNT ON

    SET @MENSAJE='';
    DECLARE @IDMOVGC INT =0;
    DECLARE @NUMTRANSACCION INT =0;

    IF @IDLIQUIDACION>0
    BEGIN
        --Borrar registros de  pagos y asientos 
        SELECT 
            @IDMOVGC=IDMOVGC ,@NUMTRANSACCION=NUMDOCUME
        FROM GC_MOV_C
        WHERE NUMDOCUMEREL=CAST(@IDLIQUIDACION AS VARCHAR(30))
        AND DESCRIPCION like 'CAUSACION PAGO LIQUIDACION VACACIONES'
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

        UPDATE TH_LIQUIDACIONVACACIONES
        SET CONTABILIZADO=0--, DEVENGADO=(DEVENGADO/0.92)
        WHERE IDLIQUIDACIONVACACIONES=@IDLIQUIDACION; 
        
        
    END
    ELSE
    BEGIN            
        SET @MENSAJE='No se envio el numero de transacción';
    END

END