"""Prueba técnica Spark; no reemplaza los seis productores ni el forecast del proyecto."""
import sys
from pyspark.sql import SparkSession
spark=SparkSession.builder.appName('RetailSmart-Batch-Demo').getOrCreate()
df=spark.read.json(sys.argv[1])
assert df.count()>0, 'No hay filas Bronze'
df.write.mode('overwrite').parquet(sys.argv[2])
print('SILVER_PARQUET_OK',sys.argv[2])
spark.stop()
