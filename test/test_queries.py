from rdflib import Graph, URIRef, Literal, BNode
import os
import sys
import shutil
import requests
import pandas
from urllib import parse

import unittest

ENDPOINT = "http://localhost:8080/sparql"

# Check if endpoint is reachable.
try:
    response = requests.get("/".join(os.path.split(ENDPOINT)[:-1]))
    assert response.status_code == 200

except: 
    raise RuntimeError("Could not connect to ontop endpoint %s. Is ontop endpoint up and running?" % ENDPOINT)

class QueriesTest(unittest.TestCase):
    """ :class QueriesTest: Test class hosting all test queries. """

    def setUp(self):
        """ Setup run at the beginning of each test method."""

        # Setup a graph.
        self._graph = Graph()

        # Empty list to collect files and dirs created during tests. These will be
        #+ deleted after the test ends (see `tearDown()` below).
        self._thrash = []

    def tearDown(self):
        """ Teardown method run at the end of each test method. """

        for item in self._thrash:
            if os.path.isfile(item):
                os.remove(item)
            elif os.path.isdir(item):
                shutil.rmtree(item)

    def test_dataset_type_relations(self):
        """ There must be one and only one rdf:type relation for datasets (issue #5)."""

        graph = self._graph

        query_string = f"""
prefix ome_core: <http://www.openmicroscopy.org/rdf/2016-06/ome_core/>

select (count(distinct ?tp) as ?n_types) where {{
    SERVICE <{ENDPOINT}> {{
            ?s a ome_core:Dataset;
                a ?tp .
    }}
}}
"""
        response = graph.query(query_string)

        for r in response:
            print(r)

        self.assertEqual(len(response), 1)
        self.assertEqual(int([r.n_types for r in response][0]), 1)

    def test_dataset_type_value(self):
        """ A ome_core:Dataset instance must be of type ome_core:Dataset (issue #5)."""

        query_string = f"""
prefix ome_core: <http://www.openmicroscopy.org/rdf/2016-06/ome_core/>

select distinct ?tp where {{
    SERVICE <{ENDPOINT}> {{
            ?s a ome_core:Dataset;
                a ?tp .
    }}
}}
"""
        response = self._graph.query(query_string)

        for r in response:
            print(r)

        self.assertIn(URIRef("http://www.openmicroscopy.org/rdf/2016-06/ome_core/Dataset"), [r.tp for r in response])

    def test_number_of_projects_datasets_images(self):
        """ Check a query on the count of projects, datasets, and images. """

        graph = self._graph

        query_string = f"""
prefix ome_core: <http://www.openmicroscopy.org/rdf/2016-06/ome_core/>

select ?n_projects ?n_datasets ?n_images where {{
    SERVICE <{ENDPOINT}> {{
    {{
      select (count(?project) as ?n_projects) where {{
        ?project a ome_core:Project .
      }}
    }}
    {{
      select (count(?dataset) as ?n_datasets) where {{
        ?dataset a ome_core:Dataset .
        }}
    }}
    {{
      select (count(?image) as ?n_images) where {{
        ?image a ome_core:Image .
      }}
    }}
  }}
}}
"""

        # Run the query.
        response = graph.query(query_string)

        # Test.
        self.assertEqual(len(response), 1)

        # Check numbers.
        number_of_objects = [r for r in response][0]
        self.assertEqual(int(number_of_objects.n_projects), 1)
        self.assertEqual(int(number_of_objects.n_datasets), 3)
        self.assertEqual(int(number_of_objects.n_images  ),  10)

    def test_project(self):
        """ Test number of projects in the VKG. """

        graph = self._graph

        query_string = f"""
        prefix ome_core: <http://www.openmicroscopy.org/rdf/2016-06/ome_core/>

        SELECT distinct ?s WHERE {{
          SERVICE <{ENDPOINT}> {{
            ?s a ome_core:Project .
          }}
        }}
        limit 3
        """

        # Run the query.
        response = graph.query(query_string)

        # Test.
        self.assertEqual(len(response), 1)
 
    def test_dataset(self):
        """ Test that there are 3 datasets in the graph db"""
        
        graph = self._graph

        query_string = f"""
        prefix ome_core: <http://www.openmicroscopy.org/rdf/2016-06/ome_core/>

        SELECT distinct ?ds WHERE {{
          SERVICE <{ENDPOINT}> {{
            ?ds a ome_core:Dataset .
          }}
        }}
        limit 3
        """

        # Run the query.
        response = graph.query(query_string)

        # Test.
        self.assertEqual(len(response), 3)
  
    def test_image(self):
        """ Test number of images in VKG. """
        
        graph = self._graph

        query_string = f"""
        prefix ome_core: <http://www.openmicroscopy.org/rdf/2016-06/ome_core/>

        SELECT distinct ?s WHERE {{
          SERVICE <{ENDPOINT}> {{
            ?s a ome_core:Image .
          }}
        }}
        limit 100
        """

        # Run the query.
        response = graph.query(query_string)
        for r in response:
            print(r)

        # Test.
        self.assertEqual(len(response), 10)

    def test_project_dataset_image(self):
        """ Test a query for a project-dataset-image hierarchy. """

        graph = self._graph

        query_string = f"""
        prefix ome_core: <http://www.openmicroscopy.org/rdf/2016-06/ome_core/>

        SELECT distinct ?project ?dataset ?image ?image_name  WHERE {{
          SERVICE <{ENDPOINT}> {{
            ?project a ome_core:Project ;
                     ome_core:dataset ?dataset .
            ?dataset a ome_core:Dataset ;
                     ome_core:image ?image .
            ?image a ome_core:Image ;
                   rdfs:label ?image_name .
        }}
        }}
        """

        # Run the query.
        response = graph.query(query_string)

        # Should get 10 images.
        self.assertEqual(len(response), 10)

    def test_image_key_value(self):
        """ Test querying for an image property via the mapannotation key."""

        graph = self._graph

        query_string = f"""
        prefix ome_core: <http://www.openmicroscopy.org/rdf/2016-06/ome_core/>
        prefix dc: <http://purl.org/dc/terms/>

        SELECT distinct ?img ?author ?subject ?provenance WHERE {{
          SERVICE <{ENDPOINT}> {{
            ?img a ome_core:Image;
                 dc:contributor ?author;
                 dc:subject ?subject.
         }}
        }}
        """

        # Run the query.
        response = graph.query(query_string)
        for r in response:
            print(r.img, r.author, r.subject)

        self.assertEqual(len(response), 10)

    def test_project_key_value(self):
        """ Test querying for a project property via the mapannotation key."""

        graph = self._graph

        query_string = f"""
        prefix ome_core: <http://www.openmicroscopy.org/rdf/2016-06/ome_core/>
        prefix dc: <http://purl.org/dc/terms/>

        SELECT distinct ?project ?author ?subject ?provenance WHERE {{
          SERVICE <{ENDPOINT}> {{
            ?project a ome_core:Project;
                 dc:contributor ?author;
                 dc:subject ?subject;
                 dc:provenance ?provenance.
         }}
        }}
        """

        # Run the query.
        response = graph.query(query_string)

        for r in response:
            print(r.project, r.author, r.subject, r.provenance)

        self.assertEqual(len(response), 1)

    def test_dataset_key_value(self):
        """ Test querying for an dataset property via the mapannotation key."""

        graph = self._graph

        query_string = f"""
        prefix ome_core: <http://www.openmicroscopy.org/rdf/2016-06/ome_core/>
        prefix dc: <http://purl.org/dc/terms/>

        SELECT distinct ?dataset ?author ?subject ?provenance WHERE {{
          SERVICE <{ENDPOINT}> {{
            ?dataset a ome_core:Dataset;
                 dc:contributor ?author;
                 dc:provenance ?provenance;
                 dc:subject ?subject.
         }}
        }}
        """

        # Run the query.
        response = graph.query(query_string)

        for r in response:
            print(r.dataset, r.author, r.subject, r.provenance)

        self.assertEqual(len(response), 3)

    def test_tagged_dataset(self):
        """ Test querying all tagged datasets and their tag(s). """


        query = """

        prefix ome_core: <http://www.openmicroscopy.org/rdf/2016-06/ome_core/>
        SELECT distinct ?s ?tag WHERE {
            ?s a ome_core:Dataset;
               ome_core:tagAnnotationValue ?tag.
        }
        """
        escapedQuery = parse.quote(query)
        requestURL = ENDPOINT + "?query=" + escapedQuery
        response = requests.get(requestURL).json()
        bindings = response['results']['bindings']

        self.assertEqual(len(bindings), 1)
        self.assertEqual(bindings[0]['tag']['value'], 'TestTag')

    def test_tagged_images(self):
        """ Test querying all tagged images and their tag(s). """


        query = """

        prefix ome_core: <http://www.openmicroscopy.org/rdf/2016-06/ome_core/>
        SELECT distinct ?s ?tag WHERE {
            ?s a ome_core:Image;
               ome_core:tagAnnotationValue ?tag.
        }
        """
        escapedQuery = parse.quote(query)
        requestURL = ENDPOINT + "?query=" + escapedQuery
        response = requests.get(requestURL).json()
        bindings = response['results']['bindings']

        # All images (10) are tagged.
        self.assertEqual(len(bindings), 10)

        # They're all tagged "Screenshot"
        self.assertEqual(len(set([b['tag']['value'] for b in bindings])), 1)
        self.assertEqual(bindings[0]['tag']['value'], "Screenshot")

    def test_image_properties(self):
        """ Check Image instances have all expected properties. """
        query = """prefix ome_core: <http://www.openmicroscopy.org/rdf/2016-06/ome_core/>
SELECT distinct ?s ?prop WHERE {
    ?s a ome_core:Image;
        ?prop ?val .
}
"""
        response_df = run_query(query)

        expected_properties = [
            "http://www.w3.org/2000/01/rdf-schema#label",
            "http://www.openmicroscopy.org/rdf/2016-06/ome_core/tagAnnotationValue",
            "http://www.openmicroscopy.org/rdf/2016-06/ome_core/experimenterGroup",
            "http://www.w3.org/1999/02/22-rdf-syntax-ns#type",
            "http://purl.org/dc/terms/subject",
            "http://purl.org/dc/terms/contributor",
            "http://purl.org/dc/terms/date"
        ]

        for expected_property in expected_properties:
            self.assertIn(expected_property, response_df.prop.unique())

        print(response_df)


def run_query(query_string, endpoint=ENDPOINT, return_as_df=True):
    """ Run the query against the configured endpoint.

    :param query_string: The unescaped sparql query.
    :example query_string: 'select * where {?s ?p ?o .} limit 10'

    :param endpoint: The sparql endpoint URL.

    :param return_as_df: if true: return query results as pandas dataframe, if false: return as returned from requests.get().
    """

    escapedQuery = parse.quote(query_string)
    requestURL = ENDPOINT + "?query=" + escapedQuery

    response = requests.get(requestURL, timeout=600).json()

    if return_as_df:
        return response_frame(response)

    return response


def response_frame(response):
    """ Convert http response to pandas dataframe. """

    response_vars = response['head']['vars']
    response_bindings = response['results']['bindings']
    tmp = [dict([(var,binding[var]['value']) for var in response_vars]) for binding in response_bindings]

    return pandas.DataFrame(data=tmp)

if __name__ == "__main__":
    unittest.main()
