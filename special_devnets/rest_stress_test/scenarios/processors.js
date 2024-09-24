module.exports = {
    logResponseSize: (requestParams, response, context, ee, next) => {
        // Calculate the response size in bytes
        const responseSizeBytes = JSON.stringify(response.body).length + JSON.stringify(response.headers).length;
        // Convert bytes to kilobytes and log the value
        const responseSizeKB = responseSizeBytes / 1024;

        // Log to console
        console.log(`Response Size: ${responseSizeKB.toFixed(2)} KB`);

        return next(); // Continue to the next action
    }
};

