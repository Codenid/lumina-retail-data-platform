import io
import json
import os
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "soluciones", "api-insights"))
import main


def request(path, query="", method="GET"):
    status_headers = {}

    def start_response(status, headers):
        status_headers["status"] = status
        status_headers["headers"] = dict(headers)

    environ = {
        "REQUEST_METHOD": method,
        "PATH_INFO": path,
        "QUERY_STRING": query,
        "wsgi.input": io.BytesIO(b""),
    }
    body = b"".join(main.app(environ, start_response))
    return status_headers, json.loads(body)


class RetailSmartApiTests(unittest.TestCase):
    @patch.object(main, "fetch_rows", return_value=[{"sample": 1}])
    def test_four_business_routes_return_gold_data(self, fetch_rows):
        expectations = {
            "/api/v1/insights": {"insights_streaming", "cu01_riesgo_quiebre_despacho"},
            "/api/v1/kpis": {"cu03_kpis_operativos"},
            "/api/v1/inventory-plans": {"cu02_plan_reposicion"},
            "/api/v1/maintenance-risks": {"cu04_alertas_mantenimiento"},
        }
        for path, tables in expectations.items():
            with self.subTest(path=path):
                result, payload = request(path, "limit=5&scenario_id=batch-001")
                self.assertEqual(result["status"], "200 OK")
                self.assertTrue(payload)
                self.assertEqual({call.args[0] for call in fetch_rows.call_args_list}, tables)
                fetch_rows.reset_mock()

    @patch.object(main, "fetch_rows", return_value=[])
    def test_health_does_not_query_bigquery(self, fetch_rows):
        result, payload = request("/healthz")
        self.assertEqual(result["status"], "200 OK")
        self.assertEqual(payload, {"status": "ok"})
        fetch_rows.assert_not_called()

    def test_limit_and_scenario_are_validated(self):
        result, payload = request("/api/v1/kpis", "limit=1000")
        self.assertEqual(result["status"], "400 Bad Request")
        self.assertEqual(payload["error"], "invalid_query")
        result, payload = request("/api/v1/kpis", "scenario_id=bad%20id")
        self.assertEqual(result["status"], "400 Bad Request")

    def test_unknown_route_and_method_are_rejected(self):
        result, payload = request("/unknown")
        self.assertEqual(result["status"], "404 Not Found")
        self.assertEqual(payload["error"], "route_not_found")
        result, payload = request("/api/v1/kpis", method="POST")
        self.assertEqual(result["status"], "405 Method Not Allowed")
        self.assertEqual(result["headers"]["Allow"], "GET")


if __name__ == "__main__":
    unittest.main()
