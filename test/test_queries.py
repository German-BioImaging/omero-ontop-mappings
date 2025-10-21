from rdflib import Graph, URIRef, Literal, BNode
import os
import sys
import shutil
import requests
import pandas
import pprint
from urllib import parse

import unittest

ENDPOINT = "http://localhost:8080/sparql"

# --- Helper for order-independent pair checks 
def as_pairs(df, left, right):
    """
    Convert two DataFrame columns into a list of paired tuples.

    This helper is used when query results might come back
    in a different row order (SPARQL queries through Ontop).
    """
    #Extract the values from the left column as a list.
    left_values = df[left].tolist()

    #Extract the values from the right column as a list.
    right_values = df[right].tolist()

    #Combine both lists element-by-element into pairs.
    # Example: ["A", "B"], ["1", "2"] → [("A", "1"), ("B", "2")]
    paired = list(zip(left_values, right_values))

    return paired

# Check if endpoint is reachable.
def check_endpoint():
    try:
        response = requests.get("/".join(os.path.split(ENDPOINT)[:-1]))
        assert response.status_code == 200

    except: 
        raise RuntimeError("Could not connect to ontop endpoint %s. Is ontop endpoint up and running?" % ENDPOINT)


# Test helpers
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
    """ Convert http response to pandas dataframe.

    :param response: The return from a requests.get() .

    :return: The values of response['results']['bindings'] and vars as a pandas.DataFrame.
    :rtype: pandas.DataFrame
    """

    response_vars = response['head']['vars']
    response_bindings = response['results']['bindings']
    tmp = [dict([(var,binding[var]['value']) for var in response_vars]) for binding in response_bindings]

    return pandas.DataFrame(data=tmp)

class QueriesTest(unittest.TestCase):
    """ :class QueriesTest: Test class hosting all test queries. """

    @classmethod
    def setUpClass(cls):

        check_endpoint()

        return super().setUpClass()

    def setUp(self):
        """ Setup run at the beginning of each test method."""

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
        """ There must be one and only one rdf:type relation for datasets (issue #5).
        Erratum: Since workaround of https://github.com/joshmoore/ome-ld/issues/6 most instances now have to rdf:type relations, one
        in the omekg ontology, one in the ome core ontology.
        """


        query_string = f"""
prefix ome_core: <https://ld.openmicroscopy.org/core/>

select (count(distinct ?tp) as ?n_types) where {{
            ?s a ome_core:Dataset;
                a ?tp .
}}
"""
        response = run_query(query_string)

        print(response.to_string())
        self.assertEqual(len(response), 1)
        self.assertEqual(int(response.loc[0, 'n_types']), 2)

    def test_dataset_type_value(self):
        """ A ome_core:Dataset instance must be of type ome_core:Dataset (issue #5)."""

        query_string = f"""
prefix ome_core: <https://ld.openmicroscopy.org/core/>

select distinct ?tp where {{
    SERVICE <{ENDPOINT}> {{
            ?s a ome_core:Dataset;
                a ?tp .
    }}
}}
"""
        response = self._graph.query(query_string)

        self.assertIn(URIRef("https://ld.openmicroscopy.org/core/Dataset"), [r.tp for r in response])

    def test_number_of_projects_datasets_images(self):
        """ Check a query on the count of projects, datasets, and images. """

        graph = self._graph

        query_string = f"""
prefix ome_core: <https://ld.openmicroscopy.org/core/>

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
        self.assertEqual(int(number_of_objects.n_images  ),  12)
        self.assertEqual(int(number_of_objects.n_datasets), 3)
        self.assertEqual(int(number_of_objects.n_projects), 1)

    def test_number_of_project(self):
        """ Test number of projects in the VKG. """

        graph = self._graph

        query_string = f"""
        prefix ome_core: <https://ld.openmicroscopy.org/core/>

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

    def test_project_owner_group(self):
        """ Test project ownership """

        query_string = f"""
        prefix ome_core: <https://ld.openmicroscopy.org/core/>
        prefix omekg:  <https://ld.openmicroscopy.org/omekg/>
        prefix omeprop:  <https://ld.openmicroscopy.org/omekg#>


        SELECT distinct ?project ?owner ?group WHERE {{
            ?project a ome_core:Project ;
        ome_core:experimenter ?owner;
        ome_core:experimenter_group ?group .
        }}
        """

        # Run the query.
        response = run_query(query_string)

        print("\n" + response.to_string())


        self.assertTupleEqual((1,3), response.shape)

    def test_owner_aliases(self):
        """ Test all equivalent properties to owner work alike. """

        query_string = f"""
        prefix ome_core: <https://ld.openmicroscopy.org/core/>


        SELECT ?alias_owner_prop WHERE {{
            ?project a ome_core:Project ;
                     ome_core:experimenter ?owner;
                     ?alias_owner_prop ?owner .
        }}
        """

        # Run the query.
        response = run_query(query_string)

        print("\n" + response.to_string())

        # There should be three equivalent properties.
        self.assertEqual(len(response), 3)

    def test_group_aliases(self):
        """ Test all equivalent properties to group work alike. """

        query_string = f"""
        prefix ome_core: <https://ld.openmicroscopy.org/core/>


        SELECT ?alias_group_prop WHERE {{
            ?project a ome_core:Project ;
                     ome_core:experimenter_group ?group;
                     ?alias_group_prop ?group .
        }}
        """

        # Run the query.
        response = run_query(query_string)

        print("\n" + response.to_string())

        # There should be three equivalent properties.
        self.assertEqual(len(response), 3)

    def test_group_name(self):
        """ Test the name property on groups. """

        query_string = f"""
        prefix dc: <http://purl.org/dc/elements/1.1/>
        prefix foaf: <http://xmlns.com/foaf/0.1/>
        prefix ome_core: <https://ld.openmicroscopy.org/core/>
        prefix omekg:  <https://ld.openmicroscopy.org/omekg/>
        prefix omeprop:  <https://ld.openmicroscopy.org/omekg#>

        SELECT * where {{
            ?group a omekg:Group ;
                   dc:identifier ?group_id;
                   foaf:name ?name .
        }}
        """

        # Run the query.
        response = run_query(query_string).set_index('group_id')

        print("\n" + response.to_string())

        self.assertEqual(response.loc['0', 'name'], 'system')
        self.assertEqual(response.loc['1', 'name'], 'user')
        self.assertEqual(response.loc['2', 'name'], 'guest')

    def test_owner_name(self):
        """ Test the name property on owners. """

        query_string = f"""
        prefix dc: <http://purl.org/dc/elements/1.1/>
        prefix foaf: <http://xmlns.com/foaf/0.1/>
        prefix ome_core: <https://ld.openmicroscopy.org/core/>
        prefix omekg:  <https://ld.openmicroscopy.org/omekg/>
        prefix omeprop:  <https://ld.openmicroscopy.org/omekg#>

        SELECT * where {{
            ?owner a omekg:Experimenter ;
                   dc:identifier ?owner_id;
                   foaf:name ?name .
        }}
        """

        # Run the query.
        response = run_query(query_string).set_index('owner_id')

        self.assertEqual(response.loc['0', 'name'], 'root root')
        self.assertEqual(response.loc['1', 'name'], 'Guest Account')

    def test_dataset_core(self):
        """ Test query with the core prefix and ontology. """

        query_string = f"""
        prefix ome_core: <https://ld.openmicroscopy.org/core/>

        SELECT distinct ?ds WHERE {{
            ?ds a ome_core:Dataset .
        }}
        limit 10
        """

        # Run the query.
        response = run_query(query_string)

        print(response.to_string())

        # Test.
        self.assertEqual(len(response), 3)

    def test_dataset(self):
        """ Test that there are 3 datasets in the graph db"""

        query_string = f"""
        prefix ome_core: <https://ld.openmicroscopy.org/core/>
        prefix omekg: <https://ld.openmicroscopy.org/omekg/>
        prefix omekgprops: <https://ld.openmicroscopy.org/omekg#>

        SELECT distinct ?ds WHERE {{
            ?ds a ome_core:Dataset .
        }}
        limit 3
        """

        # Run the query.
        response_df = run_query(query_string)

        # Test.
        self.assertEqual(len(response_df), 3)

    def test_image(self):
        """ Test number of images in VKG. """

        graph = self._graph

        query_string = f"""
        prefix ome_core: <https://ld.openmicroscopy.org/core/>

        SELECT distinct ?s WHERE {{
          SERVICE <{ENDPOINT}> {{
            ?s a ome_core:Image .
          }}
        }}
        """

        # Run the query.
        response = graph.query(query_string)

        # Test.
        self.assertEqual(len(response), 12)

    def test_project_dataset_image(self):
        """ Test a query for a project-dataset-image hierarchy. """

        query_string = """
        prefix ome_core: <https://ld.openmicroscopy.org/core/>
        prefix omekg: <https://ld.openmicroscopy.org/omekg/>
        prefix omeprop: <https://ld.openmicroscopy.org/omekg#>

        SELECT distinct ?project ?dataset ?image ?image_name  WHERE {{
            ?project a ome_core:Project ;
                     ome_core:dataset ?dataset .
            ?dataset a ome_core:Dataset ;
                     ome_core:image ?image .
            ?image a ome_core:Image ;
                   rdfs:label ?image_name .
        }}
        """

        # Run the query.
        response = run_query(query_string)

        # Should get 10 images.
        self.assertEqual(len(response), 12)

    def test_image_key_value(self):
        """ Test querying for an image property via the mapannotation key."""

        graph = self._graph

        query_string = f"""
        prefix ome_core: <https://ld.openmicroscopy.org/core/>
        prefix dc: <http://purl.org/dc/terms/>

        SELECT distinct ?img ?author ?subject WHERE {{
          SERVICE <{ENDPOINT}> {{
            ?img a ome_core:Image;
                 dc:contributor ?author;
                 dc:subject ?subject.
         }}
        }}
        """

        # Run the query.
        response = graph.query(query_string)

        for item in response:
            print(item)

        self.assertEqual(len(response), 12)

    def test_project_key_value(self):
        """ Test querying for a project property via the mapannotation key."""

        graph = self._graph

        query_string = f"""
        prefix ome_core: <https://ld.openmicroscopy.org/core/>
        prefix dcterms: <http://purl.org/dc/terms/>

        SELECT distinct ?project ?author ?subject WHERE {{
          SERVICE <{ENDPOINT}> {{
            ?project a ome_core:Project;
                 dcterms:contributor ?author;
                 dcterms:subject ?subject;
         }}
        }}
        """

        # Run the query.
        response = graph.query(query_string)

        self.assertEqual(len(response), 1)

    def test_dataset_key_value(self):
        """ Test querying for an dataset property via the mapannotation key."""


        query_string = f"""
        prefix ome_core: <https://ld.openmicroscopy.org/core/>
        prefix dc: <http://purl.org/dc/terms/>

        SELECT distinct ?dataset ?author ?subject ?provenance WHERE {{
            ?dataset a ome_core:Dataset;
                 dc:contributor ?author;
                 dc:provenance ?provenance;
                 dc:subject ?subject.
        }}
        """

        # Run the query.
        response = run_query(query_string)

        self.assertEqual(len(response), 3)

    def test_tagged_dataset(self):
        """ Test querying all tagged datasets and their tag(s). """

        query = """

        prefix ome_core: <https://ld.openmicroscopy.org/core/>
        prefix kgprops: <https://ld.openmicroscopy.org/omekg#>
        select distinct * where {
            ?s a ome_core:Dataset;
               kgprops:tag_annotation_value ?tag.
        }
        """

        response = run_query(query)
        self.assertEqual(len(response), 1)
        self.assertEqual(response.loc[0, 'tag'], 'TestTag')

    def test_tagged_images(self):
        """ Test querying all tagged images and their tag(s). """


        query = """

        prefix ome_core: <https://ld.openmicroscopy.org/core/>
        prefix kgprops: <https://ld.openmicroscopy.org/omekg#>
        SELECT distinct ?s ?tag WHERE {
            ?s a ome_core:Image;
               kgprops:tag_annotation_value ?tag.
        }
        """
        response = run_query(query)

        # All images (10) are tagged.
        self.assertEqual(len(response), 12)

        # They're all tagged "Screenshot"
        self.assertEqual(response.loc[0, 'tag'], "Screenshot")

    def test_image_roi(self):
        """ Test querying image with ROI. """

        query = """
prefix ome_core: <https://ld.openmicroscopy.org/core/>
prefix kg: <https://ld.openmicroscopy.org/omekg/>
prefix kgprops: <https://ld.openmicroscopy.org/omekg#>
select ?img ?roi where {
    ?roi a ome_core:ROI .
    ?img a ome_core:Image;
         ^ome_core:image ?roi .
}
"""

        # Run query.
        results = run_query(query)

        print(results.to_string())

        expected = [
        ("https://example.org/site/Image/11", "https://example.org/site/ROI/1"),
        ("https://example.org/site/Image/12", "https://example.org/site/ROI/2"),
        ]
        # Actual pairs from the query results (order may vary)
        actual = as_pairs(results, "img", "roi")
        print("Actual pairs:", actual)
        # Check that actual pairs match expected, ignoring order.
        self.assertCountEqual(actual, expected)

    def test_image_properties(self):
        """ Check Image instances have all expected properties. """
        query = """prefix ome_core: <https://ld.openmicroscopy.org/core/>
SELECT distinct ?prop WHERE {
    ?s a ome_core:Image;
        ?prop ?val .
}
"""
        response_df = run_query(query)

        expected_properties = [
            "http://purl.org/dc/elements/1.1/identifier",
            "http://www.w3.org/2000/01/rdf-schema#label",
            "https://ld.openmicroscopy.org/omekg#tag_annotation_value",
            "http://www.w3.org/1999/02/22-rdf-syntax-ns#type",
            "http://purl.org/dc/terms/subject",
            "http://purl.org/dc/terms/contributor",
            "http://purl.org/dc/terms/date",
        ]

        for expected_property in expected_properties:
            self.assertIn(expected_property, response_df.prop.unique())

    def test_namespace_fixing_non_uri(self):
        """ Test that non-URI namespaces are correctly fixed """
        query = """
PREFIX ome_core: <https://ld.openmicroscopy.org/core/>
PREFIX image: <https://example.org/site/Image/>
PREFIX ome_ns: <http://www.openmicroscopy.org/ns/default/>

SELECT DISTINCT * WHERE {
  image:11 ome_ns:sampletype ?st .
}
"""
        response_df = run_query(query)

        self.assertEqual(response_df.iloc[0,0], 'screen')

    def test_namespace_fixing_no_ns(self):
        """ Test that empty namespaces are set to a default value."""
        query = """
PREFIX ome_core: <https://ld.openmicroscopy.org/core/>
PREFIX image: <https://example.org/site/Image/>
PREFIX ome_ns: <http://www.openmicroscopy.org/ns/default/>

SELECT DISTINCT * WHERE {
  image:12 ome_ns:annotator ?st .
}
"""
        response_df = run_query(query)

        self.assertEqual(response_df.iloc[0,0], 'MrX')

    def test_namespace_fixing_issue16(self):
        """ Test that empty namespaces are set to a default value."""
        query = """
PREFIX ome_core: <https://ld.openmicroscopy.org/core/>
PREFIX image: <https://example.org/site/Image/>
PREFIX ome_ns: <http://www.openmicroscopy.org/ns/default/>

SELECT DISTINCT * WHERE {
  image:10 ome_ns:Assay ?assay .
}
"""
        response_df = run_query(query)

        print(response_df.to_string())

        self.assertEqual(response_df.iloc[0,0], 'PRTSC')

    def test_namespace_fixing_issue17(self):
        """ Test that namespaces starting with "/" are correctly fixed."""
        query = """
PREFIX ome_core: <https://ld.openmicroscopy.org/core/>
PREFIX image: <https://example.org/site/Image/>
PREFIX ome_ns: <http://www.openmicroscopy.org/ns/default/>

SELECT DISTINCT * WHERE {
  image:9 ome_ns:Assay ?assay .
}
"""
        response_df = run_query(query)

        self.assertEqual(response_df.iloc[0,0], 'Bruker')

    def test_experimenter_property(self):
        """ Test the experimenter property links to the owner in projects, datasets, images. """

        query_string = """
        prefix omekg: <https://ld.openmicroscopy.org/omekg/>
        prefix omeprop: <https://ld.openmicroscopy.org/omekg#>

        SELECT distinct ?project ?dataset ?image ?image_name ?project_owner ?dataset_owner ?image_owner WHERE {{
            ?project a omekg:Project ;
                     omeprop:dataset ?dataset ;
                     omeprop:experimenter ?project_owner .
            ?dataset a omekg:Dataset ;
                     omeprop:image ?image ;
                     omeprop:experimenter ?dataset_owner .
            ?image a omekg:Image ;
                   rdfs:label ?image_name ;
                   omeprop:experimenter ?image_owner .
        }}
        """

        # Run the query.
        response = run_query(query_string)

        print("\n"+response.to_string())


    @unittest.expectedFailure
    def test_screen(self):
        """ Test query for a screen."""

        query = """
        prefix omekg: <https://ld.openmicroscopy.org/omekg/>
        prefix omeprop: <https://ld.openmicroscopy.org/omekg#>

        SELECT *
        where {{
            ?screen a omekg:Screen .
        }}
        """

        results = run_query(query)

        print("\n"+results.to_string())

        self.assertEqual(1, len(results))

    @unittest.expectedFailure
    def test_plate(self):
        """ Test query for a plate."""

        query = """
        prefix omekg: <https://ld.openmicroscopy.org/omekg/>
        prefix omeprop: <https://ld.openmicroscopy.org/omekg#>

        SELECT *
        where {{
            ?plate a omekg:Plate .
        }}
        """

        results = run_query(query)

        print("\n"+results.to_string())

        self.assertEqual(1, len(results))

    @unittest.expectedFailure
    def test_screen_plate(self):
        """ Test query for screen and related plate."""
        results = run_query("""
        prefix omekg: <https://ld.openmicroscopy.org/omekg/>
        prefix omeprop: <https://ld.openmicroscopy.org/omekg#>

        SELECT *
        where {{
            ?plate a omekg:Plate ;
                   omeprop:screen ?screen .
            ?screen a omekg:Screen .
        }}
        """)

        print("\n"+results.to_string())

        self.assertTupleEqual((1, 2), results.shape)

    @unittest.expectedFailure
    def test_plate_acquisition(self):
        """ Test query for plate and plate acquisition."""

        results = run_query("""
        prefix omekg: <https://ld.openmicroscopy.org/omekg/>
        prefix omeprop: <https://ld.openmicroscopy.org/omekg#>

        SELECT *
        where {{
            ?plate a omekg:Plate ;
                   ^omeprop:plate ?acq .
            ?acq a omekg:PlateAcquisition .
        }}
        """)

        print("\n"+results.to_string())

        self.assertTupleEqual( (1,2), results.shape )

    @unittest.expectedFailure
    def test_plate_well(self):
        """ Test query for plate-acquisition and well. """

        results = run_query("""
        prefix omekg: <https://ld.openmicroscopy.org/omekg/>
        prefix omeprop: <https://ld.openmicroscopy.org/omekg#>

        SELECT *
        where {{
            ?plate a omekg:Plate ;
                   ^omeprop:plate ?well .
            ?well a omekg:Well .
        }}
        """)

        print("\n"+results.to_string())

        self.assertTupleEqual((384, 2), results.shape)

    @unittest.expectedFailure
    def test_well_sample(self):
        """ Test query for well and well sample."""

        results = run_query("""
        prefix omekg: <https://ld.openmicroscopy.org/omekg/>
        prefix omeprop: <https://ld.openmicroscopy.org/omekg#>

        SELECT *
        where {{
            ?well a omekg:Well ;
                   ^omeprop:well ?ws .
            ?ws a omekg:WellSample .
        }}
        """)

        print("\n"+results.to_string())

        # 384 wells x 4 samples per well
        self.assertTupleEqual((384*4, 2), results.shape)


    @unittest.expectedFailure
    def test_well_sample_image(self):
        """ Test query for  well sample and image. """

        results = run_query("""
        prefix omekg: <https://ld.openmicroscopy.org/omekg/>
        prefix omeprop: <https://ld.openmicroscopy.org/omekg#>

        SELECT *
        where {{
            ?ws a omekg:WellSample ;
                   omeprop:image ?img .
            ?img a omekg:Image .
        }}
        """)

        print("\n"+results.to_string())

        self.assertTupleEqual((1536, 2), results.shape)

    @unittest.expectedFailure
    def test_plateAcquisition(self):
        """ Test query for a PlateAcquisition."""

        query = """
        prefix omekg: <https://ld.openmicroscopy.org/omekg/>
        prefix omeprop: <https://ld.openmicroscopy.org/omekg#>

        SELECT *
        where {{
            ?plate_acquisition a omekg:PlateAcquisition .
        }}
        """

        results = run_query(query)

        print("\n"+results.to_string())

        self.assertEqual(1, len(results))

    def test_reagent_1(self):
        """ Test query for a reagent."""

        query = """
        prefix omekg: <https://ld.openmicroscopy.org/omekg/>
        prefix omeprop: <https://ld.openmicroscopy.org/omekg#>

        SELECT *
        where {{
            ?reagent a omekg:Reagent .
        }}
        """

        results = run_query(query)

        print("\n"+results.to_string())

        self.assertEqual(0, len(results))

    @unittest.expectedFailure
    def test_plate_key_value(self):
        """ Test querying for plate kv annotations as properties and values. """

        query_string = f"""
        prefix ome_core: <https://ld.openmicroscopy.org/core/>
        prefix dc: <http://purl.org/dc/terms/>
        prefix omens: <http://www.openmicroscopy.org/ns/default/>

        SELECT distinct ?key WHERE {{
            ?img a ome_core:Plate;
                 ?kvterm ?val .
        filter(strstarts(str(?kvterm), str(omens:)))
        bind(strafter(str(?kvterm), str(omens:)) as ?key)
        }}
        order by ?key

        """

        # Run the query.
        results = run_query(query_string)

        print("\n"+results.to_string())

        self.assertTupleEqual((13,1), results.shape)

        self.assertIn("CellLineMutation", results['key'].values)

    @unittest.expectedFailure
    def test_well_key_value(self):
        """ Test querying for a well kv-annotations as property value pairs."""

        query_string = f"""
        prefix ome_core: <https://ld.openmicroscopy.org/core/>
        prefix dc: <http://purl.org/dc/terms/>
        prefix omens: <http://www.openmicroscopy.org/ns/default/>

        SELECT distinct ?key ?val WHERE {{
            ?img a ome_core:Well;
                 ?kvterm ?val .
        filter(strstarts(str(?kvterm), str(omens:)))
        bind(strafter(str(?kvterm), str(omens:)) as ?key)
        }}
        order by ?key

        """

        # Run the query.
        results = run_query(query_string)

        # Convert to Series for easier querying.
        results = results.set_index('key')['val']

        print("\n"+results.to_string())

        self.assertTupleEqual((39,), results.shape)

        self.assertEqual("NCBITaxon_9606", results['TermSource1Accession'])
        self.assertEqual('0.610481812', results["nseg.0.m.eccentricity.mean"])

    @unittest.expectedFailure
    def test_wellsample(self):
        """ Test querying for a wellsample. """

        query_string = f"""
        prefix ome_core: <https://ld.openmicroscopy.org/core/>
        prefix dc: <http://purl.org/dc/terms/>
        prefix omens: <http://www.openmicroscopy.org/ns/default/>

        SELECT distinct ?wellsample WHERE {{
            ?wellsample a ome_core:WellSample.
        }}

        """

        # Run the query.
        results = run_query(query_string)

        # There should be 1536 WellSamples.
        self.assertTupleEqual((1536,1), results.shape)

    def test_reagents(self):
        """ Test querying for multiple reagents. """

        query_string = f"""
        prefix ome_core: <https://ld.openmicroscopy.org/core/>
        prefix dc: <http://purl.org/dc/terms/>
        prefix omens: <http://www.openmicroscopy.org/ns/default/>

        SELECT distinct * WHERE {{
            ?wellsample a ome_core:Reagent.
        }}

        """

        # Run the query. It should return an empty results set.
        results = run_query(query_string)

        # There should be 0 Reagents.
        self.assertTupleEqual((0,0), results.shape)

    def test_pixels(self):
        """ Test querying for a Pixels object. """

        query_string = f"""
  prefix omekg: <https://ld.openmicroscopy.org/omekg/>
  prefix omeprop: <https://ld.openmicroscopy.org/omekg#>
  prefix foaf: <http://xmlns.com/foaf/0.1/>

  select ?image (min(?pixelsize_x) as ?min_size)  {{
    ?px a omekg:Pixels;
        omeprop:image ?image ;
         omeprop:physical_size_x ?pixelsize_x ;
   }}
        group by ?image
        order by desc(?min_size)
        """

        # Run the query. It should return an empty results set.
        results = run_query(query_string)

        print('\n' + results.to_string())

    def test_channels(self):
        """ Test querying for Channels object. """

        query_string = f"""
      prefix omekg: <https://ld.openmicroscopy.org/omekg/>
    prefix omeprop: <https://ld.openmicroscopy.org/omekg#>
    prefix foaf: <http://xmlns.com/foaf/0.1/>
    select ?pixels (min(?red) as ?min_red) (min(?green) as ?min_green) (min(?blue) as ?min_blue) (max(?red) as ?max_red) (max(?green) as ?max_green) (max(?blue) as ?max_blue)
  where {{
      ?channel a omekg:Channel;
               omeprop:pixels ?pixels;
               omeprop:red ?red;
               omeprop:green ?green;
               omeprop:blue ?blue .
     }}
  group by ?pixels
  limit 100
        """

        results = run_query(query_string).set_index('pixels').astype(int)

        print("\n" + results.to_string())

        self.assertEqual(results['min_red'].sum(), 0)
        self.assertTrue(all(results['max_blue'] == 255))


if __name__ == "__main__":
    unittest.main()
