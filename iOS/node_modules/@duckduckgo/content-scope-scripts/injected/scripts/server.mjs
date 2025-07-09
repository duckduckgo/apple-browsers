import { createServer } from 'http-server';

const server = createServer({ root: process.env.SERVER_DIR });
server.listen(process.env.SERVER_PORT);
server.server.on('listening', () => {
    process.send?.({ port: server.server.address().port });
});
server.server.on('error', () => {
    process.exit(1);
});
