$graph:
- class: Workflow
  doc: Main stage manager
  id: main
  inputs:
    aoi:
      doc: area of interest as a bounding box
      id: aoi
      label: area of interest
      type: string
    aws_access_key_id:
      type: string
    aws_secret_access_key:
      type: string
    bands:
      default:
      - green
      - nir
      doc: bands used for the NDWI
      id: bands
      label: bands used for the NDWI
      type: string[]
    endpoint_url:
      type: string
    epsg:
      default: EPSG:4326
      doc: EPSG code
      id: epsg
      label: EPSG code
      type: string
    region_name:
      type: string
    s3_bucket:
      type: string
    stac_items:
      doc: list of staged Sentinel-2 COG STAC items
      id: stac_items
      label: Sentinel-2 STAC items
      type: string[]
    sub_path:
      type: string
  label: macro-cwl
  outputs:
    s3_catalog_output:
      id: s3_catalog_output
      outputSource:
      - node_stage_out/s3_catalog_output
      type: string
    stac_catalog:
      outputSource:
      - node_stage_out/stac_catalog_out
      type: Directory
  requirements:
    InlineJavascriptRequirement: {}
    ScatterFeatureRequirement: {}
    SubworkflowFeatureRequirement: {}
  steps:
    node_stage_in:
      in:
        input: stac_items
      out:
      - stac_items_out
      run:
        arguments:
        - $( inputs.input )
        baseCommand:
        - python
        - stage.py
        class: CommandLineTool
        cwlVersion: v1.0
        id: stage
        inputs:
          input:
            type: string?
        outputs:
          stac_items_out:
            outputBinding:
              glob: .
            type: Directory
        requirements:
          DockerRequirement:
            dockerPull: ghcr.io/terradue/ogc-eo-application-package-hands-on/stage:1.3.2
          EnvVarRequirement:
            envDef:
              A: '2'
          InitialWorkDirRequirement:
            listing:
            - entry: "import pystac\nimport stac_asset\nimport asyncio\nimport os\n\
                import sys\n\nconfig = stac_asset.Config(warn=True)\nasync def main(href:\
                \ str):\n    item = pystac.read_file(href)\n    os.makedirs(item.id,\
                \ exist_ok=True)\n    cwd = os.getcwd()\n    os.chdir(item.id)\n \
                \   item = await stac_asset.download_item(item=item, directory=\"\
                .\", config=config)\n    os.chdir(cwd)  \n    cat = pystac.Catalog(id=\"\
                catalog\",\n            description=f\"catalog with staged {item.id}\"\
                ,\n            title=f\"catalog with staged {item.id}\",)\n    cat.add_item(item)\n\
                \    cat.normalize_hrefs(\"./\")\n    cat.save(catalog_type=pystac.CatalogType.SELF_CONTAINED)\n\
                \    return cat\n    \nhref = sys.argv[1]\ncat = asyncio.run(main(href))"
              entryname: stage.py
          InlineJavascriptRequirement: {}
      scatter: input
      scatterMethod: dotproduct
    node_stage_out:
      in:
        aws_access_key_id: aws_access_key_id
        aws_secret_access_key: aws_secret_access_key
        endpoint_url: endpoint_url
        region_name: region_name
        s3_bucket: s3_bucket
        sub_path: sub_path
        wf_outputs: on_stage/stac_catalog
      out:
      - s3_catalog_output
      - stac_catalog_out
      run:
        arguments:
        - $( inputs.wf_outputs.path )
        - $( inputs.s3_bucket )
        - $( inputs.sub_path )
        baseCommand:
        - python
        - stage.py
        class: CommandLineTool
        cwlVersion: v1.0
        doc: Stage-out the results to S3
        id: stage-out
        inputs:
          aws_access_key_id:
            type: string
          aws_secret_access_key:
            type: string
          endpoint_url:
            type: string
          region_name:
            type: string
          s3_bucket:
            type: string
          sub_path:
            type: string
          wf_outputs:
            type: Directory
        outputs:
          s3_catalog_output:
            outputBinding:
              outputEval: ${  return "s3://" + inputs.s3_bucket + "/" + inputs.sub_path
                + "/catalog.json"; }
            type: string
          stac_catalog_out:
            outputBinding:
              glob: .
            type: Directory
        requirements:
          DockerRequirement:
            dockerPull: ghcr.io/terradue/ogc-eo-application-package-hands-on/stage:1.3.2
          EnvVarRequirement:
            envDef:
              aws_access_key_id: $( inputs.aws_access_key_id )
              aws_endpoint_url: $( inputs.endpoint_url )
              aws_region_name: $( inputs.region_name )
              aws_secret_access_key: $( inputs.aws_secret_access_key )
          InitialWorkDirRequirement:
            listing:
            - entry: "import os\nimport sys\nimport pystac\nimport botocore\nimport\
                \ boto3\nimport shutil\nfrom pystac.stac_io import DefaultStacIO,\
                \ StacIO\nfrom urllib.parse import urlparse\n\ncat_url = sys.argv[1]\n\
                bucket = sys.argv[2]\nsubfolder = sys.argv[3]\n\naws_access_key_id\
                \ = os.environ[\"aws_access_key_id\"]\naws_secret_access_key = os.environ[\"\
                aws_secret_access_key\"]\nregion_name = os.environ[\"aws_region_name\"\
                ]\nendpoint_url = os.environ[\"aws_endpoint_url\"]\n\nshutil.copytree(cat_url,\
                \ \"/tmp/catalog\")\ncat = pystac.read_file(os.path.join(\"/tmp/catalog\"\
                , \"catalog.json\"))\n\nclass CustomStacIO(DefaultStacIO):\n    \"\
                \"\"Custom STAC IO class that uses boto3 to read from S3.\"\"\"\n\n\
                \    def __init__(self):\n        self.session = botocore.session.Session()\n\
                \        self.s3_client = self.session.create_client(\n          \
                \  service_name=\"s3\",\n            use_ssl=True,\n            aws_access_key_id=aws_access_key_id,\n\
                \            aws_secret_access_key=aws_secret_access_key,\n      \
                \      endpoint_url=endpoint_url,\n            region_name=region_name,\n\
                \        )\n\n    def write_text(self, dest, txt, *args, **kwargs):\n\
                \        parsed = urlparse(dest)\n        if parsed.scheme == \"s3\"\
                :\n            self.s3_client.put_object(\n                Body=txt.encode(\"\
                UTF-8\"),\n                Bucket=parsed.netloc,\n               \
                \ Key=parsed.path[1:],\n                ContentType=\"application/geo+json\"\
                ,\n            )\n        else:\n            super().write_text(dest,\
                \ txt, *args, **kwargs)\n\n\nclient = boto3.client(\n    \"s3\",\n\
                \    aws_access_key_id=aws_access_key_id,\n    aws_secret_access_key=aws_secret_access_key,\n\
                \    endpoint_url=endpoint_url,\n    region_name=region_name,\n)\n\
                \nStacIO.set_default(CustomStacIO)\n\nfor item in cat.get_items():\n\
                \    for key, asset in item.get_assets().items():\n        s3_path\
                \ = os.path.normpath(\n            os.path.join(os.path.join(subfolder,\
                \ item.id, asset.href))\n        )\n        print(f\"upload {asset.href}\
                \ to s3://{bucket}/{s3_path}\",file=sys.stderr)\n        client.upload_file(\n\
                \            asset.get_absolute_href(),\n            bucket,\n   \
                \         s3_path,\n        )\n        asset.href = f\"s3://{bucket}/{s3_path}\"\
                \n        item.add_asset(key, asset)\n\ncat.normalize_hrefs(f\"s3://{bucket}/{subfolder}\"\
                )\n\nfor item in cat.get_items():\n    # upload item to S3\n    print(f\"\
                upload {item.id} to s3://{bucket}/{subfolder}\", file=sys.stderr)\n\
                \    pystac.write_file(item, item.get_self_href())\n\n# upload catalog\
                \ to S3\nprint(f\"upload catalog.json to s3://{bucket}/{subfolder}\"\
                , file=sys.stderr)\npystac.write_file(cat, cat.get_self_href())\n\n\
                print(f\"s3://{bucket}/{subfolder}/catalog.json\", file=sys.stdout)"
              entryname: stage.py
          InlineJavascriptRequirement: {}
          ResourceRequirement: {}
    on_stage:
      in:
        aoi: aoi
        bands: bands
        epsg: epsg
        stac_items: node_stage_in/stac_items_out
      out:
      - stac_catalog
      run: '#water_bodies'
- class: Workflow
  doc: Water bodies detection based on NDWI and otsu threshold
  id: water_bodies
  inputs:
    aoi:
      doc: area of interest as a bounding box
      label: area of interest
      type: string
    bands:
      default:
      - green
      - nir
      doc: bands used for the NDWI
      label: bands used for the NDWI
      type: string[]
    epsg:
      default: EPSG:4326
      doc: EPSG code
      label: EPSG code
      type: string
    stac_items:
      doc: list of staged Sentinel-2 COG STAC items
      label: Sentinel-2 STAC items
      type: Directory[]
  label: Water bodies detection based on NDWI and otsu threshold
  outputs:
  - id: stac_catalog
    outputSource:
    - node_stac/stac_catalog
    type: Directory
  requirements:
  - class: ScatterFeatureRequirement
  - class: SubworkflowFeatureRequirement
  steps:
    node_stac:
      in:
        item: stac_items
        rasters:
          source: node_water_bodies/detected_water_body
      out:
      - stac_catalog
      run: '#stac'
    node_water_bodies:
      in:
        aoi: aoi
        bands: bands
        epsg: epsg
        item: stac_items
      out:
      - detected_water_body
      run: '#detect_water_body'
      scatter: item
      scatterMethod: dotproduct
- class: Workflow
  doc: Water body detection based on NDWI and otsu threshold
  id: detect_water_body
  inputs:
    aoi:
      doc: area of interest as a bounding box
      type: string
    bands:
      doc: bands used for the NDWI
      type: string[]
    epsg:
      default: EPSG:4326
      doc: EPSG code
      type: string
    item:
      doc: staged STAC item
      type: Directory
  label: Water body detection based on NDWI and otsu threshold
  outputs:
  - id: detected_water_body
    outputSource:
    - node_otsu/binary_mask_item
    type: File
  requirements:
  - class: ScatterFeatureRequirement
  steps:
    node_crop:
      in:
        aoi: aoi
        band: bands
        epsg: epsg
        item: item
      out:
      - cropped
      run: '#crop'
      scatter: band
      scatterMethod: dotproduct
    node_normalized_difference:
      in:
        rasters:
          source: node_crop/cropped
      out:
      - ndwi
      run: '#norm_diff'
    node_otsu:
      in:
        raster:
          source: node_normalized_difference/ndwi
      out:
      - binary_mask_item
      run: '#otsu'
- arguments: []
  baseCommand:
  - python
  - -m
  - app
  class: CommandLineTool
  hints:
    DockerRequirement:
      dockerPull: ghcr.io/terradue/ogc-eo-application-package-hands-on/crop:1.3.2
  id: crop
  inputs:
    aoi:
      inputBinding:
        prefix: --aoi
      type: string
    band:
      inputBinding:
        prefix: --band
      type: string
    epsg:
      inputBinding:
        prefix: --epsg
      type: string
    item:
      inputBinding:
        prefix: --input-item
      type: Directory
  outputs:
    cropped:
      outputBinding:
        glob: '*.tif'
      type: File
  requirements:
    EnvVarRequirement:
      envDef:
        PATH: /srv/conda/envs/env_crop/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        PROJ_LIB: /srv/conda/envs/env_crop/share/proj/
        PYTHONPATH: /workspaces/ogc-eo-application-package-hands-on/water-bodies/command-line-tools/crop:/home/jovyan/ogc-eo-application-package-hands-on/water-bodies/command-line-tools/crop:/home/jovyan/water-bodies/command-line-tools/crop:/workspaces/vscode-binder/command-line-tools/crop
    InlineJavascriptRequirement: {}
    ResourceRequirement:
      coresMax: 2
      ramMax: 2028
- arguments: []
  baseCommand:
  - python
  - -m
  - app
  class: CommandLineTool
  hints:
    DockerRequirement:
      dockerPull: ghcr.io/terradue/ogc-eo-application-package-hands-on/norm_diff:1.3.2
  id: norm_diff
  inputs:
    rasters:
      inputBinding:
        position: 1
      type: File[]
  outputs:
    ndwi:
      outputBinding:
        glob: '*.tif'
      type: File
  requirements:
    EnvVarRequirement:
      envDef:
        PATH: /srv/conda/envs/env_norm_diff/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        PROJ_LIB: /srv/conda/envs/env_norm_diff/share/proj/
        PYTHONPATH: /workspaces/ogc-eo-application-package-hands-on/water-bodies/command-line-tools/norm_diff:/home/jovyan/ogc-eo-application-package-hands-on/water-bodies/command-line-tools/norm_diff:/workspaces/vscode-binder/command-line-tools/norm_diff
    InlineJavascriptRequirement: {}
    ResourceRequirement:
      coresMax: 2
      ramMax: 2028
- arguments: []
  baseCommand:
  - python
  - -m
  - app
  class: CommandLineTool
  hints:
    DockerRequirement:
      dockerPull: ghcr.io/terradue/ogc-eo-application-package-hands-on/otsu:1.3.2
  id: otsu
  inputs:
    raster:
      inputBinding:
        position: 1
      type: File
  outputs:
    binary_mask_item:
      outputBinding:
        glob: '*.tif'
      type: File
  requirements:
    EnvVarRequirement:
      envDef:
        PATH: /srv/conda/envs/env_otsu/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        PROJ_LIB: /srv/conda/envs/env_otsu/share/proj/
        PYTHONPATH: /workspaces/ogc-eo-application-package-hands-on/water-bodies/command-line-tools/otsu:/home/jovyan/ogc-eo-application-package-hands-on/water-bodies/command-line-tools/otsu:/workspaces/vscode-binder/command-line-tools/otsu
    InlineJavascriptRequirement: {}
    ResourceRequirement:
      coresMax: 2
      ramMax: 2028
- arguments: []
  baseCommand:
  - python
  - -m
  - app
  class: CommandLineTool
  hints:
    DockerRequirement:
      dockerPull: ghcr.io/terradue/ogc-eo-application-package-hands-on/stac:1.3.2
  id: stac
  inputs:
    item:
      type:
        inputBinding:
          prefix: --input-item
        items: Directory
        type: array
    rasters:
      type:
        inputBinding:
          prefix: --water-body
        items: File
        type: array
  outputs:
    stac_catalog:
      outputBinding:
        glob: .
      type: Directory
  requirements:
    EnvVarRequirement:
      envDef:
        PATH: /srv/conda/envs/env_stac/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        PROJ_LIB: /srv/conda/envs/env_stac/lib/python3.9/site-packages/rasterio/proj_data
        PYTHONPATH: /workspaces/ogc-eo-application-package-hands-on/water-bodies/command-line-tools/stac:/home/jovyan/ogc-eo-application-package-hands-on/water-bodies/command-line-tools/stac:/workspaces/vscode-binder/command-line-tools/stac
    InlineJavascriptRequirement: {}
    ResourceRequirement:
      coresMax: 2
      ramMax: 2028
$namespaces:
  s: https://schema.org/
cwlVersion: v1.0
s:softwareVersion: 1.3.2
schemas:
- http://schema.org/version/9.0/schemaorg-current-http.rdf
