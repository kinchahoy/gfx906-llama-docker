docker build -t llama-gfx906-swap .
docker compose up -d


The docker file runs a script in this directory that copies gfx906 params from the local machine into the docker volume, then runs ./llama-server. You can override settings with

editing the .env then run with docker compose up -d

Edit the dockerfile with the new image as things update



