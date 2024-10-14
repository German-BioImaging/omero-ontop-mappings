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
        prefix mpieb: <https://ome.evolbio.mpg.de/api/v0/m/> 
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
        assert len(response) == 3
 
    def test_mapannotation(self):
        """ Test a query for map annotation, map, key, and value. """

        graph = self._graph

        query_string = f"""
        prefix mpieb: <https://ome.evolbio.mpg.de/api/v0/m/> 
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

        keys = [str(r.key) for r in response]

        self.assertIn("http://purl.org/dc/terms/subject", keys)
        self.assertIn("http://purl.org/dc/terms/contributor", keys)
        self.assertIn("http://purl.org/dc/terms/provenance", keys)


        
if __name__ == "__main__":
    unittest.main()
