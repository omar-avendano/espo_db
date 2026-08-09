USE [ESPO]
GO
/****** Object:  StoredProcedure [dbo].[sp_OP_BORRARORDENCOMPRA]    Script Date: 8/4/2025 5:19:01 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[sp_OP_BORRARORDENCOMPRA]
@IDORDEN INT =0,
@FECHA DATE,
@USERNAME VARCHAR(60) ,
@MENSAJE varchar(150) OUTPUT
AS
BEGIN
SET NOCOUNT ON

    DECLARE @IDMM_FACTURA INT =0
    DECLARE @IDMM_OC_SO INT =0

    SET @MENSAJE=''

    IF @IDORDEN>0
        BEGIN 
            
            SELECT TOP 1 @IDMM_FACTURA=IDMM_FACTURA
                FROM MM_FACTURA
                WHERE IDMM_OC=@IDORDEN

            IF @IDMM_FACTURA>0 
                BEGIN
                    SET @MENSAJE='La orden tiene facturas activas, por favor eliminelas para que se pueda borrar el registro.'
                     
                END   
            ELSE
                BEGIN
                    --Traer el ID de la solicitud para liberarla
                    SELECT TOP 1 @IDMM_OC_SO =IDMM_OC_SO FROM MM_OC WHERE IDMM_OC=@IDORDEN
                    --Borrar registros de detalle
                    DELETE FROM MM_OC_DETALLE WHERE IDMM_OC=@IDORDEN 
                    --Borrar cabecera
                    DELETE FROM MM_OC WHERE IDMM_OC=@IDORDEN 
                    --Actualizar Solicitud de Orden de Compra
                    UPDATE MM_OC_SO SET IDMM_OC_ESTADO=1 WHERE IDMM_OC_SO=@IDMM_OC_SO

                     SET @MENSAJE='La orden se elimino correctamente.'

                END        
                    
        END
    ELSE 
        BEGIN
            SET @MENSAJE='No llegaron bien los parametros' 
        END

END