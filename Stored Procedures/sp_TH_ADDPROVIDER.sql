USE [ESPO]
GO
/****** Object:  StoredProcedure [dbo].[sp_TH_ADDPROVIDER]    Script Date: 8/6/2025 3:33:30 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[sp_TH_ADDPROVIDER]
@IDHOJAVIDA INT =0,
@FECHA DATE,
@USERNAME VARCHAR(60) ,
@MENSAJE varchar(150) OUTPUT
AS
BEGIN
SET NOCOUNT ON

    DECLARE @IDPROVEEDOR INT =0
    DECLARE @ESTADO CHAR(1) =''
    SET @MENSAJE=''

    IF @IDHOJAVIDA>0
        BEGIN 
            SELECT TOP 1 @IDPROVEEDOR=IDPROVEEDOR
                FROM TH_HV 
                JOIN GC_PROVEEDOR  ON GC_PROVEEDOR.NUMIDENTIFICACION=TH_HV.NUMIDENTIFICACION
                WHERE TH_HV.IDHOJAVIDA=@IDHOJAVIDA 

            IF @IDPROVEEDOR=0
                BEGIN
                    --Crear registro
                    INSERT INTO [dbo].[GC_PROVEEDOR]
                            ([IDCLIENTE]
                            ,[CODIGO]
                            ,[IDTIPOID]
                            ,[NUMIDENTIFICACION]
                            ,[DV]
                            ,[IDTPCONTRIB]
                            ,[NOMBRE]
                            ,[PRIMERNOMBRE]
                            ,[SEGUNDONOMBRE]
                            ,[PRIMERAPELLIDO]
                            ,[SEGUNDOAPELLIDO]
                            ,[AUTORETENEDOR]
                            ,[IDPVTP]
                            ,[DIRECCION]
                            ,[CONTACTO1]
                            ,[CONTACTO2]
                            ,[TELEFONO]
                            ,[TELEFONO2]
                            ,[EMAIL]
                            ,[IDCIUDAD]
                            ,[OBSERVACIONES]
                            ,[ESTADO]
                            ,[USUARIOTRCR]
                            ,[FECHATRCR]
                            ,[USUARIOTRED]
                            ,[FECHATRED]
                            ,[CTAICA]
                            ,[VALORICA]
                            ,[PORCENTAJERET])
                        SELECT TOP 1
                            1 AS IDCLIENTE
                            ,NUMIDENTIFICACION AS CODIGO
                            ,2 AS IDTIPOID
                            ,NUMIDENTIFICACION AS NUMIDENTIFICACION
                            ,'' AS DV
                            ,2 AS IDTPCONTRIB
                            ,CONCAT(PRIMERNOMBRE,' ',SEGUNDONOMBRE,' ',PRIMERAPELLIDO,' ',SEGUNDOAPELLIDO) AS NOMBRE
                            ,'' AS PRIMERNOMBRE
                            ,'' AS SEGUNDONOMBRE
                            ,'' AS PRIMERAPELLIDO
                            ,'' AS SEGUNDOAPELLIDO
                            ,'NO' AS AUTORETENEDOR
                            ,0 AS IDPVTP
                            ,DIRRESIDENCIA AS DIRECCION
                            ,'' AS CONTACTO1
                            ,'' AS CONTACTO2
                            ,TELEFONOMOVIL TELEFONO
                            ,'' AS TELEFONO2
                            ,EMAIL AS EMAIL
                            ,498 AS IDCIUDAD
                            ,'' AS OBSERVACIONES
                            ,'ACTIVO' AS ESTADO
                            ,@USERNAME AS USERNAMEUSUARIOTRCR
                            ,@FECHA AS FECHATRCR
                            ,@USERNAME USUARIOTRED
                            ,@FECHA AS FECHATRED
                            ,'23362702' AS CTAICA
                            ,0.0050 AS VALORICA
                            ,100 AS PORCENTAJERET
                    FROM TH_HV
                    WHERE IDHOJAVIDA=@IDHOJAVIDA

                    SET @MENSAJE='Empleado adicionado correctamente'
                END
            ELSE
				BEGIN
					SET @MENSAJE='El empleado ya esta creado como proveedor'
				END
        END
    ELSE 
        BEGIN
            SET @MENSAJE='No llegaron bien los parametros' 
        END

END
