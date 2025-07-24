exports.handler = async (event) => {
    const response = {
        statusCode: 200,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type'
        },
        body: JSON.stringify({
            title: "AWS Lambda API Working!",
            message: "If you can read this message, your Lambda function is deployed and functioning correctly. You can now proceed to Stage D to deploy the React application.",
            date: new Date().toISOString()
        })
    };
    
    return response;
}; 