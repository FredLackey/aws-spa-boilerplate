exports.handler = async (event) => {
    return {
        statusCode: 200,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
            title: "Test Lambda API",
            message: "Test message for unit tests",
            date: new Date().toISOString()
        })
    };
}; 