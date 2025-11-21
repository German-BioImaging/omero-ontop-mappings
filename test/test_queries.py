from rdflib import Graph, URIRef, Literal, BNode
import os
import sys
import shutil, shlex
import requests
import pandas
import pprint
import subprocess
from urllib import parse

import unittest

DEBUG = False
ENDPOINT = "http://193.196.20.26:8080/sparql"
# ENDPOINT = "http://localhost:8080/sparql"

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
def run_query(graph, query_string, endpoint=None, return_as_df=True):
    """ Run the query against the configured endpoint.

    :param query_string: The unescaped sparql query.
    :example query_string: 'select * where {?s ?p ?o .} limit 10'

    :param endpoint: The sparql endpoint URL.

    :param return_as_df: if true: return query results as pandas dataframe, if false: return as returned from requests.get().
    """
    if endpoint is not None:

        escapedQuery = parse.quote(query_string)
        requestURL = ENDPOINT + "?query=" + escapedQuery

        response = requests.get(requestURL, timeout=600)

        response_as_json = response.json()
        if return_as_df:
            return response_frame(response_as_json)

        return response

    else:
        response = graph.query(query_string)
        if return_as_df:
            return rdflib_query_response_to_df(response)
        return response


def rdflib_query_response_to_df(response):
    """Convert rdflib.sparqlresult to pandas.DataFrame"""
    column_names = [str(v) for v in response.vars]

    df = pandas.DataFrame(columns=column_names, data=[[v for v in items] for items in response])

    return df


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

def ontop_materialize(use_cache=False):


    current_working_directory = os.path.abspath(os.path.dirname(__file__))
    mappings_directory = os.path.abspath(os.path.join(current_working_directory, '..', 'omero-ontop-mappings'))
    target_rdf = os.path.join(current_working_directory, 'omero-test-infra.rdf') 
    command = f"../ontop-cli/ontop materialize --mapping=omero-ontop-mappings.obda --ontology=omero-ontop-mappings.ttl --properties=omero-ontop-mappings.properties --output {target_rdf.split('.')[0]}"
    cmd = shlex.split(command)

    if not use_cache:
        proc = subprocess.Popen(cmd, cwd=mappings_directory)

        proc.wait()

    return target_rdf

class QueriesTest(unittest.TestCase):
    """ :class QueriesTest: Test class hosting all test queries. """

    @classmethod
    def setUpClass(cls):

        ttl_path = ontop_materialize(use_cache=DEBUG)
        cls._graph = Graph().parse(ttl_path)

        cls._prefix_string = """
PREFIX dc: <http://purl.org/dc/terms/>
PREFIX dcterms: <http://purl.org/dc/terms/>
PREFIX foaf: <http://xmlns.com/foaf/0.1/>
PREFIX image: <https://example.org/site/Image/>
PREFIX obda: <https://w3id.org/obda/vocabulary#>
PREFIX omecore: <https://ld.openmicroscopy.org/core/>
PREFIX omekg: <https://ld.openmicroscopy.org/omekg#>
PREFIX omemap: <https://www.openmicroscopy.org/omemap#>
PREFIX omens: <http://www.openmicroscopy.org/ns/default/>
PREFIX owl: <http://www.w3.org/2002/07/owl#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX site: <https://example.org/site/>
PREFIX up: <http://purl.uniprot.org/core/>
PREFIX uptaxon: <http://purl.uniprot.org/taxonomy/>
PREFIX vcard: <https://www.w3.org/2006/vcard/ns#>
PREFIX well: <http://ome.evolbio.mpg.de/Well/>
PREFIX xml: <http://www.w3.org/XML/1998/namespace>
PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
"""

        return super().setUpClass()

    def setUp(self):
        """ Setup run at the beginning of each test method."""

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
prefix omecore: <https://ld.openmicroscopy.org/core/>

select (count(distinct ?tp) as ?n_types) where {{
            ?s a omecore:Dataset;
                a ?tp .
}}
"""
        response = run_query(self._graph, query_string, endpoint=None, return_as_df=True)

        self.assertEqual(len(response), 1)
        self.assertEqual(int(response.loc[0, 'n_types']), 1)

    def test_dataset_type_value(self):
        """ A omecore:Dataset instance must be of type omecore:Dataset (issue #5)."""

        query_string = f"""
prefix omecore: <https://ld.openmicroscopy.org/core/>

select distinct ?tp where {{
            ?s a omecore:Dataset;
                a ?tp .
}}
"""
        response = self._graph.query(query_string)

        self.assertIn(URIRef("https://ld.openmicroscopy.org/core/Dataset"), [r.tp for r in response])

    def test_number_of_projects_datasets_images(self):
        """ Check a query on the count of projects, datasets, and images. """

        graph = self._graph

        query_string = f"""
prefix omecore: <https://ld.openmicroscopy.org/core/>

select ?n_projects ?n_datasets ?n_images where {{
    {{
      select (count(?project) as ?n_projects) where {{
        ?project a omecore:Project .
      }}
    }}
    {{
      select (count(?dataset) as ?n_datasets) where {{
        ?dataset a omecore:Dataset .
        }}
    }}
    {{
      select (count(?image) as ?n_images) where {{
        ?image a omecore:Image .
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
        self.assertEqual(int(number_of_objects.n_images  ),  1548)
        self.assertEqual(int(number_of_objects.n_datasets), 3)
        self.assertEqual(int(number_of_objects.n_projects), 1)

    def test_number_of_project(self):
        """ Test number of projects in the VKG. """

        graph = self._graph

        query_string = f"""
        prefix omecore: <https://ld.openmicroscopy.org/core/>

        SELECT distinct ?s WHERE {{
            ?s a omecore:Project .
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
        prefix omecore: <https://ld.openmicroscopy.org/core/>
        prefix omekg:  <https://ld.openmicroscopy.org/omekg/>
        prefix omeprop:  <https://ld.openmicroscopy.org/omekg#>


        SELECT distinct ?project ?owner ?group WHERE {{
            ?project a omecore:Project ;
        omecore:experimenter ?owner;
        omecore:experimenter_group ?group .
        }}
        """

        # Run the query.
        response = run_query(self._graph, query_string)

        print("\n" + response.to_string())


        self.assertTupleEqual((1,3), response.shape)

    def test_experimenter(self):
        """ Test experimenter property on a project. """

        query_string = f"""
        prefix omecore: <https://ld.openmicroscopy.org/core/>


        SELECT ?owner WHERE {{
            ?project a omecore:Project ;
                     omecore:experimenter ?owner;
        }}
        """

        # Run the query.
        response = run_query(self._graph, query_string)

        print("\n" + response.to_string())

        # Check.
        self.assertEqual(response.loc[0, 'owner'], URIRef("https://example.org/site/Experimenter/0"))


    def test_experimenter_group(self):
        """ Test querying the group of a Project. """

        query_string = f"""
        prefix omecore: <https://ld.openmicroscopy.org/core/>

        SELECT ?group WHERE {{
            ?project a omecore:Project ;
                     omecore:experimenter_group ?group.
        }}
        """

        # Run the query.
        response = run_query(self._graph, query_string)

        print("\n" + response.to_string())

        # There should be three equivalent properties.
        self.assertEqual(response.loc[0, 'group'], URIRef("https://example.org/site/ExperimenterGroup/0"))

    def test_group_name(self):
        """ Test the name property on groups. """

        query_string = f"""
        prefix dc: <http://purl.org/dc/elements/1.1/>
        prefix omecore: <https://ld.openmicroscopy.org/core/>
        prefix omeprop:  <https://ld.openmicroscopy.org/omekg#>

        SELECT * where {{
            ?group a omecore:ExperimenterGroup ;
                   dc:identifier ?group_id;
                   rdfs:label ?name .
        }}
        """

        # Run the query.
        response = list(run_query(self._graph, query_string, return_as_df=False))

        self.assertEqual(response[0].name, Literal('system'))
        self.assertEqual(response[1].name, Literal('user'))
        self.assertEqual(response[2].name, Literal('guest'))

    def test_dataset_core(self):
        """ Test query with the core prefix and ontology. """

        query_string = f"""
        prefix omecore: <https://ld.openmicroscopy.org/core/>

        SELECT distinct ?ds WHERE {{
            ?ds a omecore:Dataset .
        }}
        limit 10
        """

        # Run the query.
        response = run_query(self._graph, query_string)

        print(response.to_string())

        # Test.
        self.assertEqual(len(response), 3)

    def test_dataset(self):
        """ Test that there are 3 datasets in the graph db"""

        query_string = f"""
        prefix omecore: <https://ld.openmicroscopy.org/core/>
        prefix omekg: <https://ld.openmicroscopy.org/omekg/>
        prefix omekgprops: <https://ld.openmicroscopy.org/omekg#>

        SELECT distinct ?ds WHERE {{
            ?ds a omecore:Dataset .
        }}
        limit 3
        """

        # Run the query.
        response_df = run_query(self._graph, query_string)

        # Test.
        self.assertEqual(len(response_df), 3)

    def test_image(self):
        """ Test number of images in VKG. """

        graph = self._graph

        query_string = f"""
        prefix omecore: <https://ld.openmicroscopy.org/core/>

        SELECT distinct ?s WHERE {{
            ?s a omecore:Image .
        }}
        """

        # Run the query.
        response = graph.query(query_string)

        # Test.
        self.assertEqual(len(response), 1548)

    def test_project_dataset_image(self):
        """ Test a query for a project-dataset-image hierarchy. """

        query_string = """
        prefix omecore: <https://ld.openmicroscopy.org/core/>
        prefix omekg: <https://ld.openmicroscopy.org/omekg#>
        prefix dcterms: <http://purl.org/dc/terms/>

        SELECT distinct ?project ?dataset ?image ?image_name  WHERE {{
            ?project a omecore:Project ;
                     dcterms:hasPart ?dataset .
            ?dataset a omecore:Dataset ;
                     dcterms:hasPart ?image .
            ?image a omecore:Image ;

        rdfs:label ?image_name .
        }}
        """

        # Run the query.
        response = run_query(self._graph, query_string)
        print("\n" + response.to_string())

        # Should get 10 images.
        self.assertEqual(len(response), 12)

    def test_image_key_value(self):
        """ Test querying for an image property via the mapannotation key."""

        graph = self._graph

        query_string = f"""
        prefix omecore: <https://ld.openmicroscopy.org/core/>
        prefix dc: <http://purl.org/dc/terms/>

        SELECT distinct ?img ?author ?subject WHERE {{
            ?img a omecore:Image;
                 dc:contributor ?author;
                 dc:subject ?subject.
        }}
        """

        # Run the query.
        response = graph.query(query_string)

        for item in response:
            print(item)

        self.assertEqual(len(response), 12)

    def test_project_key_value(self):
        """ Test querying for a project property via the mapannotation key."""

        query_string = """
        prefix omecore: <https://ld.openmicroscopy.org/core/>
        prefix dcterms: <http://purl.org/dc/terms/>

        SELECT distinct ?project ?author ?subject WHERE {{
            ?project a omecore:Project;
                 dcterms:contributor ?author;
                 dcterms:subject ?subject;
        }}
        """

        # Run the query.
        response = run_query(self._graph, query_string)

        # self.assertEqual(len(response), 1)

    def test_dataset_key_value(self):
        """ Test querying for an dataset property via the mapannotation key."""


        query_string = f"""
        prefix omecore: <https://ld.openmicroscopy.org/core/>
        prefix dc: <http://purl.org/dc/terms/>

        SELECT distinct ?dataset ?author ?subject ?provenance WHERE {{
            ?dataset a omecore:Dataset;
                 dc:contributor ?author;
                 dc:provenance ?provenance;
                 dc:subject ?subject.
        }}
        """

        # Run the query.
        response = run_query(self._graph, query_string)

        self.assertEqual(len(response), 3)

    def test_tagged_dataset(self):
        """ Test querying all tagged datasets and their tag(s). """

        query = """

        prefix omecore: <https://ld.openmicroscopy.org/core/>
        prefix kgprops: <https://ld.openmicroscopy.org/omekg#>
        select distinct * where {
            ?s a omecore:Dataset;
               kgprops:tag_annotation_value ?tag.
        }
        """

        response = run_query(self._graph, query)
        self.assertEqual(len(response), 1)
        self.assertEqual(response.loc[0, 'tag'], Literal('TestTag'))

    def test_tagged_images(self):
        """ Test querying all tagged images and their tag(s). """


        query = """

        prefix omecore: <https://ld.openmicroscopy.org/core/>
        prefix kgprops: <https://ld.openmicroscopy.org/omekg#>
        SELECT distinct ?s ?tag WHERE {
            ?s a omecore:Image;
               kgprops:tag_annotation_value ?tag.
        }
        """
        response = run_query(self._graph, query)

        # All images (10) are tagged.
        self.assertEqual(len(response), 12)

        # They're all tagged "Screenshot"
        self.assertEqual(response.loc[0, 'tag'], Literal("Screenshot"))

    def test_image_roi(self):
        """ Test querying image with ROI. """

        query = """
prefix omecore: <https://ld.openmicroscopy.org/core/>
prefix kg: <https://ld.openmicroscopy.org/omekg/>
prefix kgprops: <https://ld.openmicroscopy.org/omekg#>
select ?img ?roi where {
    ?roi a omecore:ROI .
    ?img a omecore:Image;
         ^omecore:image ?roi .
}
"""

        # Run query.
        results = run_query(self._graph, query)

        print(results.to_string())

        expected = [
        (URIRef("https://example.org/site/Image/11"), URIRef("https://example.org/site/ROI/1")),
        (URIRef("https://example.org/site/Image/12"), URIRef("https://example.org/site/ROI/2")),
        ]
        # Actual pairs from the query results (order may vary)
        actual = as_pairs(results, "img", "roi")
        print("Actual pairs:", actual)
        # Check that actual pairs match expected, ignoring order.
        self.assertCountEqual(actual, expected)

    def test_image_properties(self):
        """ Check Image instances have all expected properties. """
        query = """prefix omecore: <https://ld.openmicroscopy.org/core/>
SELECT distinct ?prop WHERE {
    ?s a omecore:Image;
        ?prop ?val .
}
"""
        response_df = run_query(self._graph, query)

        expected_properties = [
            URIRef("http://purl.org/dc/elements/1.1/identifier"),
            URIRef("http://www.w3.org/2000/01/rdf-schema#label"),
            URIRef("https://ld.openmicroscopy.org/omekg#tag_annotation_value"),
            URIRef("http://www.w3.org/1999/02/22-rdf-syntax-ns#type"),
            URIRef("http://purl.org/dc/terms/subject"),
            URIRef("http://purl.org/dc/terms/contributor"),
            URIRef("http://purl.org/dc/terms/date"),
        ]

        found_properties = [u for u in response_df.prop.unique()]

        for expected_property in expected_properties:
            self.assertIn(expected_property, found_properties)

    def test_namespace_fixing_non_uri(self):
        """ Test that non-URI namespaces are correctly fixed """
        query = """
PREFIX omecore: <https://ld.openmicroscopy.org/core/>
PREFIX image: <https://example.org/site/Image/>
PREFIX ome_ns: <http://www.openmicroscopy.org/ns/default/>

SELECT DISTINCT * WHERE {
  image:11 ome_ns:sampletype ?st .
}
"""
        response_df = run_query(self._graph, query)

        self.assertEqual(response_df.iloc[0,0], Literal('screen'))

    def test_namespace_fixing_no_ns(self):
        """ Test that empty namespaces are set to a default value."""
        query = """
PREFIX omecore: <https://ld.openmicroscopy.org/core/>
PREFIX image: <https://example.org/site/Image/>
PREFIX ome_ns: <http://www.openmicroscopy.org/ns/default/>

SELECT DISTINCT * WHERE {
  image:12 ome_ns:annotator ?st .
}
"""
        response_df = run_query(self._graph, query)

        self.assertEqual(response_df.iloc[0,0], Literal('MrX'))

    def test_namespace_fixing_issue16(self):
        """ Test that empty namespaces are set to a default value."""
        query = """
PREFIX omecore: <https://ld.openmicroscopy.org/core/>
PREFIX image: <https://example.org/site/Image/>
PREFIX ome_ns: <http://www.openmicroscopy.org/ns/default/>

SELECT DISTINCT * WHERE {
  image:10 ome_ns:Assay ?assay .
}
"""
        response_df = run_query(self._graph, query)

        print(response_df.to_string())

        self.assertEqual(response_df.iloc[0,0], Literal('PRTSC'))

    def test_namespace_fixing_issue17(self):
        """ Test that namespaces starting with "/" are correctly fixed."""
        query = """
PREFIX omecore: <https://ld.openmicroscopy.org/core/>
PREFIX image: <https://example.org/site/Image/>
PREFIX ome_ns: <http://www.openmicroscopy.org/ns/default/>

SELECT DISTINCT * WHERE {
  image:9 ome_ns:Assay ?assay .
}
"""
        response_df = run_query(self._graph, query)

        self.assertEqual(response_df.iloc[0,0], Literal('Bruker'))

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
        response = run_query(self._graph, query_string)

        print("\n"+response.to_string())


    def test_screen(self):
        """ Test query for a screen."""

        query = self._prefix_string + """

        SELECT *
        where {{
            ?screen a omecore:Screen .
        }}
        """

        results = run_query(self._graph, query)

        self.assertEqual(3, len(results))

    def test_plate(self):
        """ Test query for a plate."""

        query = self._prefix_string + """

        SELECT *
        where {{
            ?plate a omecore:Plate .
        }}
        """

        results = run_query(self._graph, query)

        print("\n"+results.to_string())

        self.assertEqual(1, len(results))

    def test_wellsample_plateacquisition(self):
        """ Test querying for WellSamples and related PlateAcquisitions."""

        query = self._prefix_string + """

        SELECT *
        where {{
            ?wellsample a omecore:WellSample ;
                        ^dcterms:hasPart ?run .
            ?run a omecore:PlateAcquisition .
        }}
        """

        results = run_query(self._graph, query, return_as_df=True)

        if DEBUG:
            print("\n" + results.to_string())

        self.assertEqual(1536, len(results))

    def test_screen_plate(self):
        """ Test query for screen and related plate."""
        results = run_query(self._graph, self._prefix_string + """

        SELECT *
        where {{
            ?plate a omecore:Plate ;
                   dcterms:relation ?screen .
            ?screen a omecore:Screen .
       }}
        """)

        self.assertTupleEqual((1, 2), results.shape)

    def test_wellsample_relations(self):
        """ Count number of relations of WellSamples. """

        results = run_query(self._graph, self._prefix_string + """

  select ?class (count(distinct ?relation) as ?n_relations) where {{
    ?wellsample a omecore:WellSample ;
                dcterms:relation ?relation .
    ?relation a ?class
  }}
  group by ?class
  order by ?n_relations
       """)

        print(results.to_string())
        self.assertTupleEqual( (1,2), results.shape )
        self.assertEqual(int(results.iloc[0,1]), 1536) # 384*4 = 1536 related images 

    def test_plate_well(self):
        """ Test query for Plate and Well."""

        query = self._prefix_string + f"""

        SELECT *
        where {{
            ?plate a omecore:Plate ;
                   dcterms:hasPart ?well .
            ?well a omecore:Well .
        }}
        """

        results = run_query(self._graph, query)

        print("\n"+results.to_string())

        self.assertTupleEqual((384, 2), results.shape)

    def test_well_sample(self):
        """ Test query for well and well sample."""

        query = self._prefix_string + f"""
        SELECT *
        where {{
            ?well a omecore:Well ;
                   dcterms:hasPart ?ws .
            ?ws a omecore:WellSample .
        }}
        """

        results = run_query(self._graph, query)

        if DEBUG:
            print("\n"+results.to_string())

        # 384 wells x 4 samples per well
        self.assertTupleEqual((384*4, 2), results.shape)

    def test_plateAcquisition(self):
        """ Test query for a PlateAcquisition."""

        query = self._prefix_string + """

        SELECT *
        where {{
            ?plate_acquisition a omecore:PlateAcquisition .
        }}
        """

        results = run_query(self._graph, query)

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

        results = run_query(self._graph, query)

        print("\n"+results.to_string())

        self.assertEqual(0, len(results))

    @unittest.expectedFailure
    def test_plate_key_value(self):
        """ Test querying for plate kv annotations as properties and values. """

        query_string = self._prefix_string + f"""

        SELECT * WHERE {{
            bind(iri(concat(str(site:), "Plate/1")) as ?plate)
            ?plate omens:foo ?foo
        }}
        order by ?key

        """

        # Run the query.
        results = run_query(self._graph, query_string)

        self.assertEqual(results.iloc[0,1], "bar")

    @unittest.expectedFailure
    def test_plateacquisition_key_value(self):
        """ Test querying for plate acquisition (run) kv annotations as properties and values. """

        query_string = self._prefix_string + f"""

        SELECT * WHERE {{
            ?run a omecore:PlateAcquisition;
                 ?prop ?val.
            filter(strstarts(str(?prop), str(omens)))
        }}
        order by ?prop
        """

        # Run the query.
        results = run_query(self._graph, query_string)

        self.assertIn("CellLineMutation", results['prop'].values)

    def test_well_key_value(self):
        """ Test querying for a well kv-annotations as property value pairs."""

        query_string = self._prefix_string + f"""

  SELECT distinct * WHERE {{
    bind(iri(concat(str(site:), "Well/96")) as ?well)
    ?well ?kvterm ?val .
    filter(strstarts(str(?kvterm), str(omens:)))
    bind(strafter(str(?kvterm), str(omens:)) as ?key)
        }}
        """

        # Run the query.
        results = run_query(self._graph, query_string)

        # Convert to Series for easier querying.
        results = results.set_index('key')['val']

        print("\n"+results.to_string())
        self.assertEqual(Literal("NCBITaxon_9606"), results[Literal('TermZZSourceZZ1ZZAccession')])
        self.assertEqual(Literal('0.601114562'), results[Literal("nseg.0.m.eccentricity.mean")])

    def test_wellsample(self):
        """ Test querying for a wellsample. """

        query_string = f"""
        prefix omecore: <https://ld.openmicroscopy.org/core/>
        prefix dc: <http://purl.org/dc/terms/>
        prefix omens: <http://www.openmicroscopy.org/ns/default/>

        SELECT distinct ?wellsample WHERE {{
            ?wellsample a omecore:WellSample.
        }}

        """

        # Run the query.
        results = run_query(self._graph, query_string)

        # There should be 1536 WellSamples.
        self.assertTupleEqual((1536,1), results.shape)

    def test_reagents(self):
        """ Test querying for multiple reagents. """

        query_string = f"""
        prefix omecore: <https://ld.openmicroscopy.org/core/>
        prefix dc: <http://purl.org/dc/terms/>
        prefix omens: <http://www.openmicroscopy.org/ns/default/>

        SELECT distinct * WHERE {{
            ?wellsample a omecore:Reagent.
        }}

        """

        # Run the query. It should return an empty results set.
        results = run_query(self._graph, query_string)

        # There should be 0 Reagents.
        self.assertTupleEqual((0,1), results.shape)

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
        results = run_query(self._graph, query_string)

        print('\n' + results.to_string())

    def test_channels(self):
        """ Test querying for Channels object. """

        query_string = f"""
    prefix omekg: <https://ld.openmicroscopy.org/omekg#>
    prefix omecore: <https://ld.openmicroscopy.org/core/>
    prefix dcterms: <http://purl.org/dc/terms/>

    select ?pixels (min(?red) as ?min_red) (min(?green) as ?min_green) (min(?blue) as ?min_blue) (max(?red) as ?max_red) (max(?green) as ?max_green) (max(?blue) as ?max_blue)
  where {{
      ?channel a omecore:Channel;
               dcterms:relation ?pixels;
               omekg:red ?red;
               omekg:green ?green;
               omekg:blue ?blue .
     }}
  group by ?pixels
  limit 100
        """

        results = run_query(self._graph, query_string).set_index('pixels').astype(int)

        print("\n" + results.to_string())

        self.assertEqual(results['min_red'].sum(), 0)
        self.assertTrue(all(results['max_blue'] == 255))


if __name__ == "__main__":
    unittest.main()
