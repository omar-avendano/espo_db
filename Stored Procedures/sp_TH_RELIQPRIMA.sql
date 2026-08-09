ALTER PROCEDURE [dbo].[sp_TH_RELIQPRIMA]
@PERIODO INT,
@FECHALIQUIDACION DATETIME ,
@USERNAME VARCHAR(60) ,
@OBSERVACIONES NVARCHAR(MAX) ,
@MENSAJE varchar(150) OUTPUT
AS
BEGIN
SET NOCOUNT ON
	--Variables Periodo
	DECLARE @IDLIQUIDACIONPRIMAC int    =0
    
	--Variables para recibir datos del cursor
	
    SELECT @IDLIQUIDACIONPRIMAC=IDNOMINALIQC FROM TH_NOMINALIQC WHERE PERIODO = @PERIODO

    IF @IDLIQUIDACIONPRIMAC>0
        BEGIN
            UPDATE TH_NOMINALIQC 
                SET 
                    FECHALIQUIDACION=@FECHALIQUIDACION, 
                    DESCRIPCION=@OBSERVACIONES,
                    ESTADO='L',
                    USUARIOTRED='@USERNAME',
                    FECHATRED=@FECHALIQUIDACION
            WHERE   
                IDNOMINALIQC=@IDLIQUIDACIONPRIMAC

            --Limpiar detalle
            DELETE FROM TH_LIQUIDACIONPRIMAD WHERE IDLIQUIDACIONPRIMAC=@IDLIQUIDACIONPRIMAC
            --Ejecutar detalle      
            exec sp_TH_LIQPRIMA_DET @IDLIQUIDACIONPRIMAC,@PERIODO ,@USERNAME
        
            SET @MENSAJE='Re liquidación creada correctamente'
            
        END
    ELSE
        BEGIN
            SET @MENSAJE='Error intentando actualizar' 
        END

END