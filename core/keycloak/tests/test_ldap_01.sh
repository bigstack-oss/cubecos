podman run -d -p 8080:8080 -p 8443:8443 --name=keycloak \
		-e KEYCLOAK_USER=admin \
		-e KEYCLOAK_PASSWORD=admin \
		-e KEYCLOAK_DEFAULT_THEME=cube \
		-e KEYCLOAK_WELCOME_THEME=cube \
		localhost/bigstack/keycloak:11.0.3

podman run -d -p 389:389 -p 636:636 --name my-openldap-container -v $SRCDIR/bootstrap.ldif:/container/service/slapd/assets/config/bootstrap/ldif/50-bootstrap.ldif docker.io/osixia/openldap --copy-service --loglevel=debug

sleep 3
podman exec my-openldap-container ldapsearch -x -H ldap://localhost -b dc=example,dc=org -D "cn=admin,dc=example,dc=org" -w admin