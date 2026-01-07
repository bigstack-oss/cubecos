#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------
# Configuration
# -------------------------------------------------
MONASCA_LIB_DIR=$1
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
BACKUP_DIR="$(pwd)/monasca-log4j-sanitized-${TIMESTAMP}"
WORK_BASE="$(pwd)/monasca-log4j-work-${TIMESTAMP}"

# Vulnerable Log4j 1.x classes (CVE-related)
VULN_PATTERNS=(
    "org/apache/log4j/net/JMSAppender.class"
    "org/apache/log4j/net/JMSSink.class"
    "org/apache/log4j/net/SocketServer.class"
    "org/apache/log4j/jdbc/JDBCAppender.class"
    "org/apache/log4j/chainsaw"
)

echo "=== Monasca JMX Log4j 1.x Sanitizer ==="
echo "Target dir : $MONASCA_LIB_DIR"
echo "Backup dir : $BACKUP_DIR"
echo

mkdir -p "$BACKUP_DIR"
mkdir -p "$WORK_BASE"

# -------------------------------------------------
# Locate relevant JARs
# -------------------------------------------------
mapfile -t TARGET_JARS < <(
    find "$MONASCA_LIB_DIR" -type f \
	 \( -name "jmxterm*-uber.jar" -o -name "jmxfetch*-jar-with-dependencies.jar" \)
)

if [[ "${#TARGET_JARS[@]}" -eq 0 ]]; then
    echo "No jmxterm or jmxfetch JARs found. Exiting."
    exit 0
fi

# -------------------------------------------------
# Process each JAR
# -------------------------------------------------
for JAR in "${TARGET_JARS[@]}"; do
    echo "Processing: $JAR"

    BASENAME="$(basename "$JAR")"
    WORK_DIR="${WORK_BASE}/${BASENAME}"

    # Backup
    cp -a "$JAR" "$BACKUP_DIR/"

    # Extract
    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR"
    (cd "$WORK_DIR" && jar xf "$JAR")

    REMOVED=0
    if [ -e $WORK_DIR/WORLDS-INF/lib/log4j.jar ] ; then
        # CVE-2015-7501 Upgrade to version: 3.2.2
        curl https://repo1.maven.org/maven2/commons-collections/commons-collections/3.2.2/commons-collections-3.2.2.jar -o $WORK_DIR/WORLDS-INF/lib/commons-collections.jar && REMOVED=1

	mkdir -p $BACKUP_DIR/WORLDS-INF/lib/log4j.jar
	( cd $BACKUP_DIR/WORLDS-INF/lib/log4j.jar && jar xf $WORK_DIR/WORLDS-INF/lib/log4j.jar && rm -f $WORK_DIR/WORLDS-INF/lib/log4j.jar )
	for PATTERN in "${VULN_PATTERNS[@]}"; do
	    if find $BACKUP_DIR/WORLDS-INF/lib/log4j.jar -path "*$PATTERN*" | grep -q .; then
		find $BACKUP_DIR/WORLDS-INF/lib/log4j.jar -path "*$PATTERN*" -exec rm -rf {} +
		echo "  - Removed $PATTERN in $BACKUP_DIR/WORLDS-INF/lib/log4j.jar"
		REMOVED=1
	    fi
	done
	if [[ "$REMOVED" -eq 1 ]]; then
	    (cd $BACKUP_DIR/WORLDS-INF/lib/log4j.jar && jar cf $WORK_DIR/WORLDS-INF/lib/log4j.jar .)
	    echo "Rebuilt sanitized $WORK_DIR/WORLDS-INF/lib/log4j.jar"
	else
	    echo "No vulnerable Log4j classes found"
	fi
    fi

    for PATTERN in "${VULN_PATTERNS[@]}"; do
	if find "$WORK_DIR" -path "*$PATTERN*" | grep -q .; then
	    find "$WORK_DIR" -path "*$PATTERN*" -exec rm -rf {} +
	    find "$WORK_DIR" -type d -wholename *META-INF/maven/log4j -exec rm -rf {} +
	    echo "  - Removed $PATTERN"
	    REMOVED=1
	fi
    done

    if [[ "$REMOVED" -eq 1 ]]; then
	(cd "$WORK_DIR" && jar cf "$JAR" .)
	echo "Rebuilt sanitized JAR"
    else
	echo "No vulnerable Log4j classes found"
    fi

    echo
done
rm -rf $WORK_BASE $BACKUP_DIR
