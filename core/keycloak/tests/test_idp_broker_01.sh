podman --namespace=keycloak run -d --net=host --name=keycloak \
		-e KEYCLOAK_USER=admin \
		-e KEYCLOAK_PASSWORD=admin \
		-e KEYCLOAK_DEFAULT_THEME=cube \
		-e KEYCLOAK_WELCOME_THEME=cube \
		localhost/bigstack/keycloak:11.0.3

# sleep 10

podman --namespace=keycloak run -d -p 8081:8080 -p 8444:8443 --name=keycloak-external \
		-e KEYCLOAK_USER=admin \
		-e KEYCLOAK_PASSWORD=admin \
		docker.io/jboss/keycloak
