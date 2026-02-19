FROM node:22-slim
WORKDIR /usr/src/app

# Files are now in the same directory as the Dockerfile
COPY package*.json ./
COPY example.js ./
COPY containerrun.js ./
COPY appsscript.json ./
# Include the hidden WIF config file
COPY .google-credentials.json ./google-credentials.json

RUN npm install

ENV PORT 8080
EXPOSE 8080

CMD ["node", "containerrun.js"]