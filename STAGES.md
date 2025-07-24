
# Stages

## Stage 1 : Hello World HTML Distribution in CloudFront
- request target account profile for aws cli (ie fred-sandbox)
- request distribution prefix to be used with all other resource paths
- deploy static site / page into cloudfront with a new distribution
- test deployment
- output deployment details in JSON to be used for subsequent stages
- test content from client using HTTP (ie curl http://{cloud-front-distribuation-url})

## Stage 2 : Deploy SSL Certificate
- request target aws cli profile for global resources (ie fred-infrastructure)
- request for FQDN(s)
- create certificate request for FQDN(s)
- create neccessary resources in Route53 for FQDN(s) and certificates
- attach certificate to the CloudFront distribution
- output deployment details in JSON to be used for subsequent stages
- test content from client using HTTPS (ie curl https://{cloud-front-distribuation-url})

## Stage 3 : Hello World API in Lambda
- use details from output of Stage 1 and Stage 2
- deploy a simple NodeJS handler to return a JSON object with the server date time
- output any new info in JSON json file
- test content from invoking the API via AWS CLI

## Stage 4 : Replace Hello World HTML with Static Hello World React App in CloudFront 
- use details from output of Stage 1 and Stage 2
- build a React Vite app with entirely static content (ie Hello React)
- replace the contents of the CloudFront distiribution with the static files for the built React Vite app 
- output any new info in JSON json file
- test content from client using HTTPS (ie curl https://{cloud-front-distribuation-url})

## Stage 5 : Replace Hello World React App with Hello JSON React App in CloudFront 
- use details from output of Stage 1, Stage 2, and Stage 3
- build a React Vite app that calls the API from the lambda and displays the JSON blob sent from the API
- replace the contents of the CloudFront distiribution with the static files for the built "Hello JSON React App" app 
- output any new info in JSON json file
- test content from client using HTTPS (ie curl https://{cloud-front-distribuation})