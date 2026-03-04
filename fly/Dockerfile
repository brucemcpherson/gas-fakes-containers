FROM node:22-slim
WORKDIR /usr/src/app

COPY package*.json ./
COPY example.js ./
COPY containerrun.js ./
COPY appsscript.json ./
COPY .google-credentials.json ./google-credentials.json

RUN npm install

ENV PORT 8080
EXPOSE 8080

CMD ["node", "containerrun.js"]
