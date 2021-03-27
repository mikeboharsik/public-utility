const exampleGetHandler = {
    method: 'GET',
    path: '/example',
    action: async () => {
        return {
            statusCode: 200,
            headers: {
                'cache-control': 'no-store',
            },
            body: 'example text',
        };  
    }
};

exports.exampleHandlers = [ exampleGetHandler ];