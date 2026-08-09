USE [ESPO]
GO
/****** Object:  StoredProcedure [dbo].[sp_TH_LIQDEFINITIVA_CONF]    Script Date: 8/8/2025 9:34:14 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[sp_TH_LIQDEFINITIVA_CONF]
    @IDHOJAVIDA INT,
    @IDNOMINALIQC INT,
    @IDSCONFIRMA VARCHAR(MAX),
    @VALSCONFIRMA VARCHAR(MAX),
    @USERNAME VARCHAR(60),
    @OBSERVACIONES NVARCHAR(MAX),
    @MENSAJE VARCHAR(150) OUTPUT
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @QRYDEL NVARCHAR(MAX) = N'';
    DECLARE @QRYUPD NVARCHAR(MAX) = N'';
    SET @MENSAJE = N'';

    IF @IDHOJAVIDA > 0
    BEGIN 
        -- BORRAR DETALLE QUE NO FUE CONFIRMADO
        IF LEN(@IDSCONFIRMA) > 0 AND @IDHOJAVIDA > 0
        BEGIN 
            DECLARE @sqlstatement NVARCHAR(MAX);
            DECLARE @IDCONCEPTO INT = 0;

            -- Construir la consulta SQL para el cursor
            SET @sqlstatement = 'DECLARE CurDetalle CURSOR FOR
                                 SELECT IDCONCEPTO FROM dbo.TH_NOMINALIQD
                                 WHERE IDHOJAVIDA = @IDHOJAVIDA
                                 AND IDNOMINALIQD NOT IN (' + @IDSCONFIRMA + ')
                                 AND IDNOMINALIQC = @IDNOMINALIQC';

            -- Ejecutar la consulta SQL
            EXEC sp_executesql @sqlstatement,
                              N'@IDHOJAVIDA INT, @IDNOMINALIQC INT',
                              @IDHOJAVIDA, @IDNOMINALIQC;

            OPEN CurDetalle
            FETCH NEXT FROM CurDetalle INTO @IDCONCEPTO

            WHILE (@@FETCH_STATUS = 0) 
            BEGIN
                IF @IDCONCEPTO = 41 -- Cesantías
                BEGIN
                    DELETE FROM dbo.TH_LIQUIDACIONCESANTIASD
                    WHERE IDLIQUIDACIONCESANTIASC = @IDNOMINALIQC AND IDHOJAVIDA = @IDHOJAVIDA;
                END
                IF @IDCONCEPTO = 43 -- Int Cesantías
                BEGIN
                    DELETE FROM dbo.TH_LIQUIDACIONINTCESANTIASD
                    WHERE IDLIQUIDACIONINTCESANTIASC = @IDNOMINALIQC AND IDHOJAVIDA = @IDHOJAVIDA;
                END

                FETCH NEXT FROM CurDetalle INTO @IDCONCEPTO
            END

            CLOSE CurDetalle
            DEALLOCATE CurDetalle

            -- Construir la consulta de eliminación
            SET @QRYDEL = 'DELETE FROM dbo.TH_NOMINALIQD
                           WHERE IDHOJAVIDA = @IDHOJAVIDA
                           AND IDNOMINALIQD NOT IN (' + @IDSCONFIRMA + ')
                           AND IDNOMINALIQC = @IDNOMINALIQC';

            EXEC sp_executesql @QRYDEL,
                              N'@IDHOJAVIDA INT, @IDNOMINALIQC INT',
                              @IDHOJAVIDA, @IDNOMINALIQC;
        END

        -- ACTUALIZAR REGISTROS CONFIRMADOS
        SET @QRYUPD = 'UPDATE dbo.TH_NOMINALIQD
                       SET CERRADO = 1
                       WHERE IDHOJAVIDA = @IDHOJAVIDA
                       AND IDNOMINALIQD IN (' + @IDSCONFIRMA + ')';

        EXEC sp_executesql @QRYUPD,
                          N'@IDHOJAVIDA INT',
                          @IDHOJAVIDA;

        IF @@ROWCOUNT > 0
        BEGIN
            --ACTUALIZAR DATOS QUE FUERON ACTUALIZADOS
            DECLARE @IDTOUPDATE INT =0
            DECLARE @VALTOUPDATE REAL =0
            DECLARE @VALORES_ACTUALIZAR NVARCHAR(MAX) = @VALSCONFIRMA
            DECLARE @TXTVALORACTUALIZAR NVARCHAR(MAX) = N''
            -- Usar STRING_SPLIT para dividir la cadena en elementos individuales
            DECLARE CurValoresActualizar CURSOR FOR
            SELECT value AS CadenaValores
            FROM STRING_SPLIT(@VALORES_ACTUALIZAR, ',')

            OPEN CurValoresActualizar
            FETCH NEXT FROM CurValoresActualizar INTO @TXTVALORACTUALIZAR

            WHILE (@@FETCH_STATUS = 0) 
            BEGIN

                SELECT * INTO #tblTemp
                FROM STRING_SPLIT(@TXTVALORACTUALIZAR, '|');

                SELECT 
                    @IDTOUPDATE=MAX(CASE WHEN rn = 1 THEN value END),
                    @VALTOUPDATE=MAX(CASE WHEN rn = 2 THEN value END)
                FROM (
                    SELECT 
                        value,
                        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
                    FROM #tblTemp
                ) AS SourceTable;

                IF(@IDTOUPDATE>0 AND @VALTOUPDATE>0.0)
                BEGIN
                    UPDATE TH_NOMINALIQD
                    SET 
                        VALOR=@VALTOUPDATE
                    WHERE IDNOMINALIQD=@IDTOUPDATE;
                END

                DROP TABLE #tblTemp 
                FETCH NEXT FROM CurValoresActualizar INTO @TXTVALORACTUALIZAR
            END
            CLOSE CurValoresActualizar
            DEALLOCATE CurValoresActualizar

            --Actualizar datos generales de liquidacion
            UPDATE TH_NOMINALIQC
                SET OBSERVACIONESLIQUIDACION=@OBSERVACIONES,
                FECHATRED=GETDATE(),
                USUARIOTRED=@USERNAME,
                USUARIOLIQUIDO=@USERNAME,
                ESTADO='L'
            WHERE IDNOMINALIQC=@IDNOMINALIQC;

            SET @MENSAJE='Registros actualizados correctamente'
        END
        ELSE 
        BEGIN
            SET @MENSAJE = 'Error actualizando registros'
        END
    END
END