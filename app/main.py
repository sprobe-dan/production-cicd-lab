from fastapi import FastAPI

app = FastAPI(
    title="Production CI/CD Lab",
    version="0.1.0",
)

@app.get("/")
def read_root() -> dict[str,str]:
    return {"message": "Production CI/CD Lab"}

@app.get("/health")
def health_check() -> dict[str, str]:
    return {"status": "healthy"}