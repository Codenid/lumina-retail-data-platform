import json,sys,unittest,subprocess,tempfile
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'automatizacion'/'utilidades'))
sys.path.insert(0,str(ROOT/'soluciones'/'procesamiento-streaming'))
from contract import normalize,canonical
from ensure import check,main

class BaselineTest(unittest.TestCase):
 def fixture(self):return json.loads((ROOT/'docs/arquitectura/contrato-evento-original.json').read_text())
 def test_contrato_real(self):
  x=self.fixture();self.assertEqual(normalize(json.dumps(x)),x)
 def test_rechaza_campo_faltante(self):
  x=self.fixture();del x['event_id']
  with self.assertRaises(ValueError):normalize(json.dumps(x))
 def test_rechaza_ruta_insegura(self):
  x=self.fixture();x['event_id']='../../otro'
  with self.assertRaises(ValueError):normalize(json.dumps(x))
 def test_serializacion_estable_para_reintentos(self):
  x=self.fixture();self.assertEqual(canonical(x),canonical(dict(reversed(list(x.items())))))
 def test_divergencia_no_se_oculta(self):
  with self.assertRaises(ValueError):check({'topic':'otro'},{'topic':'esperado'})
 def test_ubicacion_normalizada(self):check({'location':'US-CENTRAL1'},{'location':'us-central1'})
 @patch('ensure.subprocess.run')
 def test_permission_denied_nunca_crea(self,run):
  run.return_value=subprocess.CompletedProcess([],1,'','PERMISSION_DENIED: 403')
  self.assertEqual(main(['{}','describe',':::','create']),1);self.assertEqual(run.call_count,1)
 @patch('ensure.subprocess.run')
 def test_recurso_existente_no_crea(self,run):
  run.return_value=subprocess.CompletedProcess([],0,'{"topic":"ok"}','')
  self.assertEqual(main(['{"topic":"ok"}','describe',':::','create']),0);self.assertEqual(run.call_count,1)
 @patch('ensure.subprocess.run')
 def test_crea_solo_not_found_y_verifica(self,run):
  run.side_effect=[subprocess.CompletedProcess([],1,'','NOT_FOUND'),subprocess.CompletedProcess([],0,'',''),subprocess.CompletedProcess([],0,'{"topic":"ok"}','')]
  self.assertEqual(main(['{"topic":"ok"}','describe',':::','create']),0);self.assertEqual(run.call_args_list[1].args[0],['create'])
 def test_verificacion_objeto_detecta_contenido_distinto(self):
  with tempfile.TemporaryDirectory() as d:
   a=Path(d)/'a';b=Path(d)/'b';a.write_text('{"event_id":"a"}');b.write_text('{"event_id":"b"}')
   p=subprocess.run([sys.executable,str(ROOT/'automatizacion/utilidades/compare.py'),str(a),str(b)],capture_output=True)
   self.assertNotEqual(p.returncode,0)
if __name__=='__main__':unittest.main()
