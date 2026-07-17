import logging
import azure.functions as func


def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("HTTP trigger déclenché")

    name = req.params.get("name") or "World"

    return func.HttpResponse(
        f"Hello, {name}! La Function App fonctionne.",
        status_code=200
    )
