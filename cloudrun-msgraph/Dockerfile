FROM node:22-slim
WORKDIR /usr/src/app

# 1. Copy the environment-specific package.json
COPY package*.json ./
COPY example.js ./
COPY containerrun.js ./
COPY appsscript.json ./

RUN npm install


# 4. Final setup and execution
ENV PORT 8080
EXPOSE 8080

# Execute cloudrun.js from the cloudrun subdirectory
CMD ["node", "containerrun.js"]