from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

def test_read_root() -> None:
    response = client.get("/")

    assert response.status_code == 200
    assert response.json() == {"message": "Production CI/CD Lab"}

def test_health_check() -> None:
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}

def test_version() -> None:
    response = client.get("/version")

    assert response.status_code == 200
    assert response.json() == {"version": "0.1.0"}