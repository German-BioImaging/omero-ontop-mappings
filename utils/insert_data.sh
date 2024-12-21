#! /bin/bash
set -e

omero login -C -u root -w omero -s localhost:14064

# Create 3 datasets
DS1=$(omero obj new Dataset name="Dataset 1")
DS2=$(omero obj new Dataset name="Dataset 2")
DS3=$(omero obj new Dataset name="Dataset 3")
# Annotations
MAP1=$(omero obj new MapAnnotation ns=http://purl.org/dc/terms/)
omero obj new DatasetAnnotationLink parent=$DS1 child=$MAP1
omero obj map-set $MAP1 mapValue contributor "Test User"
omero obj map-set $MAP1 mapValue subject "Test images"
omero obj map-set $MAP1 mapValue provenance "Screenshots"

TAG1=$(omero tag create --name "TestTag")
omero obj new DatasetAnnotationLink parent=$DS1 child=$TAG1
# TBD: Link to DS1

MAP2=$( omero obj new MapAnnotation ns=http://purl.org/dc/terms/)
omero obj new DatasetAnnotationLink parent=$DS2 child=$MAP1
omero obj map-set $MAP2 mapValue contributor "Anonymous"
omero obj map-set $MAP2 mapValue subject "Ontop Tutorial"
omero obj map-set $MAP2 mapValue provenance "Screenshots"

MAP3=$( omero obj new MapAnnotation ns=http://purl.org/dc/terms/)
omero obj new DatasetAnnotationLink parent=$DS3 child=$MAP3
omero obj map-set $MAP3 mapValue contributor "Caligula"
omero obj map-set $MAP3 mapValue subject "OMERO Mapping"
omero obj map-set $MAP3 mapValue provenance "Screenshots"

# Create Project
PROJ=$(omero obj new Project name="Project" )
# Add to datasets to project
omero obj new ProjectDatasetLink parent=$PROJ child=$DS1
omero obj new ProjectDatasetLink parent=$PROJ child=$DS2
omero obj new ProjectDatasetLink parent=$PROJ child=$DS3

# Add project annotation.
MAP4=$(omero obj new MapAnnotation ns="http://purl.org/dc/terms/")
omero obj new ProjectAnnotationLink parent=$PROJ child=$MAP4
omero obj map-set $MAP4 mapValue contributor "Nophretete"
omero obj map-set $MAP4 mapValue subject "OMERO Ontology"
omero obj map-set $MAP4 mapValue provenance "Test Data"


# Add images
images1=$(find img/ -name "*_14-*.png" | xargs -i realpath {}) 
images2=$(find img/ -name "*_15-*.png" | xargs -i realpath {}) 
images3=$(find img/ -name "*_16-*.png" | xargs -i realpath {}) 

for img in $images1; do omero import $img -d $DS1; done
for img in $images2; do omero import $img -d $DS2; done
for img in $images3; do omero import $img -d $DS3; done

# Import images with roi into Dataset:2
images4=$(find img/ -name "*.ome.tif" | xargs -i realpath {}) 
for img in $images4; do omero import $img -d $DS2; done

TAG2=$(omero tag create --name "Screenshot")
for image_index in {1..10}; do
    ann=$(omero obj new MapAnnotation ns="http://purl.org/dc/terms/")
    omero obj new ImageAnnotationLink parent=Image:$image_index child=$ann
    omero obj map-set $ann mapValue date "$(date)"
    omero obj map-set $ann mapValue contributor "Test User"
    omero obj map-set $ann mapValue subject "Unittest"
    omero obj new ImageAnnotationLink parent=Image:$image_index child=$TAG2
done

# Add another mapannotation but do not specify the namespace.
ann=$(omero obj new MapAnnotation)
omero obj new ImageAnnotationLink parent=Image:12 child=$ann
omero obj map-set $ann mapValue annotator "MrX"

# Add another mapannotation with namespace that is not a valid URI
ann=$(omero obj new MapAnnotation ns="www.openmicroscopy.org/ns/default")
omero obj new ImageAnnotationLink parent=Image:11 child=$ann
omero obj map-set $ann mapValue sampletype "screen"

# Add another mapannotation with namespace that is not a valid URI (issue #16).
ann=$(omero obj new MapAnnotation ns="hms.harvard.edu/omero/forms/kvdata/MPB Annotations/")
omero obj new ImageAnnotationLink parent=Image:10 child=$ann
omero obj map-set $ann mapValue Assay "PRTSC"

# Add another mapannotation with namespace that starts with "/" (issue #17)
ann=$(omero obj new MapAnnotation ns="/MouseCT/Skyscan/System")
omero obj new ImageAnnotationLink parent=Image:9 child=$ann
omero obj map-set $ann mapValue Assay "Bruker"



# List all objects
today=$(date +%Y-%m-%d)
omero search Project --from=$today --to=$today
omero search Dataset --from=$today --to=$today
omero search Image   --from=$today --to=$today --date-type=import
