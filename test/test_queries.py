from rdflib import Graph
import os
import sys
import shutil

import unittest

ENDPOINT = "http://localhost:8080/sparql"

class QueriesTest(unittest.TestCase):
    
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

    def test_mapannotation(self):
        """ Test a query for map annotation, map, key, and value. """

        graph = self._graph

        query_string = f"""
        prefix ome_core: <http://www.openmicroscopy.org/rdf/2016-06/ome_core/>

        SELECT distinct ?key  WHERE {{
          SERVICE <{ENDPOINT}> {{
            ?ds a ome_core:Dataset;
                ome_core:annotation ?annotation .
            ?annotation ome_core:mapAnnotationValue ?map .
            ?map ome_core:key ?keystr;
                ome_core:value ?val ;
                ome_core:nameSpace ?ns .
            bind(iri(concat(str(?ns),str(?keystr))) as ?key)
         }}
        }}
        limit 20
        """

        # Run the query.
        response = graph.query(query_string)

        keys = set([str(r.key) for r in response])

        self.assertIn("http://purl.org/dc/terms/subject", keys)
        self.assertIn("http://purl.org/dc/terms/contributor", keys)
        self.assertIn("http://purl.org/dc/terms/provenance", keys)


    def test_key_value_query(self):
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

        self.assertEqual(len(response), 10)


if __name__ == "__main__":
    unittest.main()
