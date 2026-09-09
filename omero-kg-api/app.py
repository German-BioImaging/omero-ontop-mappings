import re

import httpx
from fastapi import FastAPI, HTTPException, Query


# Minimal REST API providing simple access to common queries
app = FastAPI(
    title="OMERO Knowledge Graph API",
    version="0.1.0",
)


# Local QLever SPARQL endpoint.
# This can later be made configurable for different deployments.
QLEVER_URL = "http://127.0.0.1:8888"


def parse_wkt_point(wkt: str):
    """
    Parse a GeoSPARQL WKT POINT and return latitude/longitude.

    WKT uses the order:
        POINT(longitude latitude)

    The REST API returns the coordinates as named latitude/longitude
    fields so clients do not need to interpret WKT directly.
    """
    match = re.fullmatch(
        r"POINT\(\s*([-+]?\d+(?:\.\d+)?)\s+([-+]?\d+(?:\.\d+)?)\s*\)",
        wkt,
    )

    if not match:
        return None

    longitude = float(match.group(1))
    latitude = float(match.group(2))

    return {
        "latitude": latitude,
        "longitude": longitude,
    }


# Search for geolocated OMERO images within a given radius.
# The REST parameters are translated into a GeoSPARQL query executed
# by QLever.
@app.get("/api/v1/images/nearby")
async def nearby_images(
    lat: float = Query(
        ...,
        ge=-90,
        le=90,
        description="Latitude of the search center",
    ),
    lon: float = Query(
        ...,
        ge=-180,
        le=180,
        description="Longitude of the search center",
    ),
    radius_km: float = Query(
        1.0,
        gt=0,
        le=1000,
        description="Search radius in kilometers",
    ),
    limit: int = Query(
        100,
        ge=1,
        le=500,
        description="Maximum number of images to return",
    ),
):
    # Build the GeoSPARQL query using the requested search position
    # and radius.
    sparql = f"""
PREFIX core: <https://ld.openmicroscopy.org/core/>
PREFIX geo: <http://www.opengis.net/ont/geosparql#>
PREFIX geof: <http://www.opengis.net/def/function/geosparql/>
PREFIX dc: <http://purl.org/dc/elements/1.1/>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX this: <https://ld.openmicroscopy.org/omekg#>

SELECT DISTINCT
    ?image
    ?id
    ?name
    ?wkt
    ?distanceKm
    ?thumbnail
    ?ome_details
WHERE {{
    ?image a core:Image ;
           dc:identifier ?id ;
           geo:hasGeometry/geo:asWKT ?wkt .

    OPTIONAL {{
        ?image rdfs:label ?name .
    }}

    OPTIONAL {{
        ?image this:thumbnail ?thumbnail .
    }}

    OPTIONAL {{
        ?image this:ome_details ?ome_details .
    }}

    BIND(
        "POINT({lon} {lat})"^^geo:wktLiteral
        AS ?queryPoint
    )

    BIND(
        geof:distance(?wkt, ?queryPoint)
        AS ?distanceKm
    )

    FILTER(?distanceKm <= {radius_km})
}}
ORDER BY ?distanceKm
LIMIT {limit}
"""

    # Send the SPARQL query to QLever and request its JSON response.
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.get(
                QLEVER_URL,
                params={"query": sparql},
            )

            response.raise_for_status()
            data = response.json()

    # Present QLever/backend errors to the REST client as HTTP 502.
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=502,
            detail=f"QLever request failed: {exc}",
        )

    # Convert the SPARQL result bindings into a simpler JSON structure.
    images = []

    for row in data["results"]["bindings"]:
        wkt = row["wkt"]["value"]

        image = {
            "id": int(row["id"]["value"]),
            "name": row.get("name", {}).get("value"),
            "distance_km": float(row["distanceKm"]["value"]),
            "location": parse_wkt_point(wkt),
            "thumbnail": row.get("thumbnail", {}).get("value"),
            "omero_url": row.get("ome_details", {}).get("value"),
        }

        images.append(image)

    return {
        "query": {
            "latitude": lat,
            "longitude": lon,
            "radius_km": radius_km,
            "limit": limit,
        },
        "returned": len(images),
        "images": images,
    }


# Retrieve metadata and hierarchical context for one OMERO image.
# In addition to image metadata, the query follows the Knowledge Graph
# relationships to its Dataset, Project, and OMERO repository.
@app.get("/api/v1/images/{image_id}")
async def get_image(image_id: int):
    sparql = f"""
PREFIX core: <https://ld.openmicroscopy.org/core/>
PREFIX geo: <http://www.opengis.net/ont/geosparql#>
PREFIX dc: <http://purl.org/dc/elements/1.1/>
PREFIX dcterms: <http://purl.org/dc/terms/>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX this: <https://ld.openmicroscopy.org/omekg#>
PREFIX omekg: <https://ld.openmicroscopy.org/omekg/>

SELECT DISTINCT
    ?image
    ?id
    ?name
    ?description
    ?wkt
    ?thumbnail
    ?ome_details
    ?dataset
    ?dataset_id
    ?dataset_name
    ?project
    ?project_id
    ?project_name
    ?repository
WHERE {{
    # Locate the image by its OMERO numeric identifier.
    ?image a core:Image ;
           dc:identifier ?id .

    FILTER(?id = {image_id})

    # Image-level metadata.
    OPTIONAL {{
        ?image rdfs:label ?name .
    }}

    OPTIONAL {{
        ?image rdfs:comment ?description .
    }}

    OPTIONAL {{
        ?image geo:hasGeometry/geo:asWKT ?wkt .
    }}

    OPTIONAL {{
        ?image this:thumbnail ?thumbnail .
    }}

    OPTIONAL {{
        ?image this:ome_details ?ome_details .
    }}

    # Follow Dataset -> Image and Project -> Dataset relationships
    # to recover the hierarchical context of the image.
    OPTIONAL {{
        ?dataset a core:Dataset ;
                 dc:identifier ?dataset_id ;
                 dcterms:hasPart ?image .

        OPTIONAL {{
            ?dataset rdfs:label ?dataset_name .
        }}

        OPTIONAL {{
            ?project a core:Project ;
                     dc:identifier ?project_id ;
                     dcterms:hasPart ?dataset .

            OPTIONAL {{
                ?project rdfs:label ?project_name .
            }}
        }}
    }}

    # Identify the OMERO repository containing the image.
    OPTIONAL {{
        ?repository a omekg:OMEROServer ;
                    dcterms:hasPart ?image .
    }}
}}
"""

    # Execute the generated SPARQL query against QLever.
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.get(
                QLEVER_URL,
                params={"query": sparql},
            )

            response.raise_for_status()
            data = response.json()

    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=502,
            detail=f"QLever request failed: {exc}",
        )

    rows = data["results"]["bindings"]

    # An empty SPARQL result means that the requested image ID is
    # not represented in the Knowledge Graph.
    if not rows:
        raise HTTPException(
            status_code=404,
            detail=f"Image {image_id} not found",
        )

    row = rows[0]

    # Optional values are represented as null in the REST response
    # when they are not present in the Knowledge Graph.
    location = None
    if "wkt" in row:
        location = parse_wkt_point(row["wkt"]["value"])

    dataset = None
    if "dataset_id" in row:
        dataset = {
            "id": int(row["dataset_id"]["value"]),
            "name": row.get("dataset_name", {}).get("value"),
        }

    project = None
    if "project_id" in row:
        project = {
            "id": int(row["project_id"]["value"]),
            "name": row.get("project_name", {}).get("value"),
        }

    repository = None
    if "repository" in row:
        repository = {
            "iri": row["repository"]["value"],
        }

    return {
        "id": int(row["id"]["value"]),
        "name": row.get("name", {}).get("value"),
        "description": row.get("description", {}).get("value"),
        "thumbnail": row.get("thumbnail", {}).get("value"),
        "omero_url": row.get("ome_details", {}).get("value"),
        "location": location,
        "dataset": dataset,
        "project": project,
        "repository": repository,
    }