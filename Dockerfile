FROM node:14-alpine
WORKDIR /usr/src/app
COPY . .
CMD ["node", "index.js"]
