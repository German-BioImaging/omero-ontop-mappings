from rdflib import Graph
import os
import sys
import shutil
import requests

import unittest

ENDPOINT = "http://localhost:8080/sparql"

# Check if endpoint is reachable.
try:
    response = requests.get("/".join(os.path.split(ENDPOINT)[:-1]))
    assert response.status_code == 200

except: 
    raise RuntimeError("Could not connect to ontop endpoint %s. Is ontop endpoint up and running?" % ENDPOINT)

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
                
    def test_project(self):
        """ Test number of projects in the VKG. """
        
        graph = self._graph

        query_string = f"""
        prefix ome_core: <http://www.openmicroscopy.org/rdf/2016-06/ome_core/>

        SELECT distinct ?s WHERE {{
          SERVICE <{ENDPOINT}> {{
            ?ds a ome_core:Project .
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



if __name__ == "__main__":
    unittest.main()
