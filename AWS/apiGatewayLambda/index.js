const { mapHandler } = require('./handlers');

exports.handler = async event => {
    const handler = mapHandler(event);
    
    /*
    if (res.headers && res.headers['cache-control']) {
        delete res.headers['cache-control'];
    }
    */

    if (handler) {
        return handler.action(event);
    }
    
    return {
        statusCode: 404,
        headers: {
            'cache-control': 'no-store',
            'content-type': 'text/html',  
        },
        body: require('fs').readFileSync('./404.html', 'utf8'),
    };
};
