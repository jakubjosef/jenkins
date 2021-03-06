#!/bin/bash -x
#
# A helper script for ENTRYPOINT.
#
# If first CMD argument is 'jenkins', then the script will bootstrap Jenkins
# If CMD argument is overriden and not 'jenkins', then the user wants to run
# his own process.

set -e

PARAMETER_TOKEN='"$@"'
ENVIRONMENT_VARIABLE_TOKEN='${JENKINS_CLI_URL}'
ENVIRONMENT_VARIABLE_SSH_TOKEN='${JENKINS_CLI_SSH}'

cat > /usr/bin/jenkins-cli <<_EOF_
#!/bin/bash
java -jar /usr/bin/jenkins/cli.jar ${PARAMETER_TOKEN}
_EOF_

cat > /usr/bin/cli <<_EOF_
#!/bin/bash
if [ -n "${ENVIRONMENT_VARIABLE_SSH_TOKEN}" ]; then
  java -jar /usr/bin/jenkins/cli.jar -s ${ENVIRONMENT_VARIABLE_TOKEN} -i ${ENVIRONMENT_VARIABLE_SSH_TOKEN} ${PARAMETER_TOKEN}
else
  java -jar /usr/bin/jenkins/cli.jar -s ${ENVIRONMENT_VARIABLE_TOKEN} ${PARAMETER_TOKEN}
fi
_EOF_

if [ "$1" = 'jenkins' ]; then

  if [ -n "${JENKINS_DELAYED_START}" ]; then
    sleep ${JENKINS_DELAYED_START}
  fi

  if [ -n "${JENKINS_ENV_FILE}" ]; then
    source ${JENKINS_ENV_FILE}
  fi

  java_vm_parameters=""
  jenkins_parameters=""
  jenkins_plugins=""

  if [ -n "${JAVA_VM_PARAMETERS}" ]; then
    java_vm_parameters=${JAVA_VM_PARAMETERS}
  fi

  if [ -n "${JENKINS_PARAMETERS}" ]; then
    jenkins_parameters=${JENKINS_PARAMETERS}
  fi

  if [ -n "${JENKINS_MASTER_EXECUTORS}" ]; then
    if [ ! -d "${JENKINS_HOME}/init.groovy.d" ]; then
      mkdir ${JENKINS_HOME}/init.groovy.d
    fi
    cat > ${JENKINS_HOME}/init.groovy.d/setExecutors.groovy <<_EOF_
  import jenkins.model.*
  import hudson.security.*

  def instance = Jenkins.getInstance()
  instance.setNumExecutors(${JENKINS_MASTER_EXECUTORS})
  instance.save()
_EOF_
  fi

  if [ -n "${JENKINS_SLAVEPORT}" ]; then
    if [ ! -d "${JENKINS_HOME}/init.groovy.d" ]; then
      mkdir ${JENKINS_HOME}/init.groovy.d
    fi
    cat > ${JENKINS_HOME}/init.groovy.d/setSlaveport.groovy <<_EOF_
  import jenkins.model.*
  import java.util.logging.Logger

  def logger = Logger.getLogger("")
  def instance = Jenkins.getInstance()
  def current_slaveport = instance.getSlaveAgentPort()
  def defined_slaveport = ${JENKINS_SLAVEPORT}

  if (current_slaveport!=defined_slaveport) {
    instance.setSlaveAgentPort(defined_slaveport)
    logger.info("Slaveport set to " + defined_slaveport)
    instance.save()
  }
_EOF_
  fi

  DEFAULT_PLUGINS="docker-workflow ant build-timeout credentials-binding email-ext github-organization-folder gradle workflow-aggregator ssh-slaves subversion timestamper ws-cleanup"

  if [ ! -n "${JENKINS_DEFAULT_PLUGINS}" ]; then
    JENKINS_PLUGINS=$JENKINS_PLUGINS" "$DEFAULT_PLUGINS
  fi

  if [ -n "${JENKINS_PLUGINS}" ]; then
    if [ ! -d "${JENKINS_HOME}/init.groovy.d" ]; then
      mkdir ${JENKINS_HOME}/init.groovy.d
    fi
    jenkins_plugins=${JENKINS_PLUGINS}
    cat > ${JENKINS_HOME}/init.groovy.d/loadPlugins.groovy <<_EOF_
    import jenkins.model.*
    import java.util.logging.Logger

    def logger = Logger.getLogger("")
    def installed = false
    def initialized = false

    def pluginParameter="${jenkins_plugins}"
    def plugins = pluginParameter.split()
    logger.info("" + plugins)
    def instance = Jenkins.getInstance()
    def pm = instance.getPluginManager()
    def uc = instance.getUpdateCenter()

    plugins.each {
      logger.info("Checking " + it)
      if (!pm.getPlugin(it)) {
        logger.info("Looking UpdateCenter for " + it)
        if (!initialized) {
          uc.updateAllSites()
          initialized = true
        }
        def plugin = uc.getPlugin(it)
        if (plugin) {
          logger.info("Installing " + it)
        	plugin.install()
          installed = true
        }
      }
    }

    if (installed) {
      logger.info("Plugins installed, you need to restart!")
      instance.save()
    }
_EOF_
  fi

  smtp_replyto_address="dummy@example.com"
  smtp_use_ssl="true"
  smtp_charset="UTF-8"

  if [ -n "${SMTP_REPLYTO_ADDRESS}" ]; then
    smtp_replyto_address=${SMTP_REPLYTO_ADDRESS}
  fi

  if [ -n "${SMTP_USE_SSL}" ]; then
    smtp_use_ssl=${SMTP_USE_SSL}
  fi

  if [ -n "${SMTP_CHARSET}" ]; then
    smtp_charset=${SMTP_CHARSET}
  fi

  if [ -n "${SMTP_USER_NAME}" ] && [ -n "${SMTP_USER_PASS}" ] && [ -n "${SMTP_HOST}" ] && [ -n "${SMTP_PORT}" ]; then
    if [ ! -d "${JENKINS_HOME}/init.groovy.d" ]; then
      mkdir ${JENKINS_HOME}/init.groovy.d
    fi
    smtp_user_name=${SMTP_USER_NAME}
    smtp_user_pass=${SMTP_USER_PASS}
    smtp_host=${SMTP_HOST}
    smtp_port=${SMTP_PORT}

    cat > ${JENKINS_HOME}/init.groovy.d/initSMTP.groovy <<_EOF_
  import jenkins.model.*

  def inst = Jenkins.getInstance()
  def desc = inst.getDescriptor("hudson.tasks.Mailer")

  desc.setSmtpAuth("${smtp_user_name}", "${smtp_user_pass}")
  desc.setReplyToAddress("${smtp_replyto_address}")
  desc.setSmtpHost("${smtp_host}")
  desc.setUseSsl(${smtp_use_ssl})
  desc.setSmtpPort("${smtp_port}")
  desc.setCharset("${smtp_charset}")

  desc.save()
  inst.save()
_EOF_
  fi

  if [ -n "${JENKINS_ADMIN_EMAIL}" ]; then
    if [ ! -d "${JENKINS_HOME}/init.groovy.d" ]; then
      mkdir ${JENKINS_HOME}/init.groovy.d
    fi
    cat > ${JENKINS_HOME}/init.groovy.d/initAdminEMail.groovy <<_EOF_
  import jenkins.model.*
  import java.util.logging.Logger

  def instance = Jenkins.getInstance()
  def jenkinsLocationConfiguration = JenkinsLocationConfiguration.get()

  jenkinsLocationConfiguration.setAdminAddress("${JENKINS_ADMIN_EMAIL}")

  jenkinsLocationConfiguration.save()
  instance.save()
_EOF_
  fi

  if [ -n "${JENKINS_ADMIN_USER}" ] && [ -n "${JENKINS_ADMIN_PASSWORD}" ]; then
    if [ ! -d "${JENKINS_HOME}/init.groovy.d" ]; then
      mkdir ${JENKINS_HOME}/init.groovy.d
    fi
    cat > ${JENKINS_HOME}/init.groovy.d/initAdmin.groovy <<_EOF_
import jenkins.model.*
import hudson.security.*
def instance = Jenkins.getInstance()
def hudsonRealm = new HudsonPrivateSecurityRealm(false)
def users = hudsonRealm.getAllUsers()
if (!users || users.empty) {
  hudsonRealm.createAccount("${JENKINS_ADMIN_USER}", "${JENKINS_ADMIN_PASSWORD}")
  instance.setSecurityRealm(hudsonRealm)
  def strategy = new GlobalMatrixAuthorizationStrategy()
  strategy.add(Jenkins.ADMINISTER, "${JENKINS_ADMIN_USER}")
  instance.setAuthorizationStrategy(strategy)
}
instance.save()
_EOF_
  fi

  if [ -n "${JENKINS_KEYSTORE_PASSWORD}" ] && [ -n "${JENKINS_CERTIFICATE_DNAME}" ]; then
    if [ ! -f "${JENKINS_HOME}/jenkins_keystore.jks" ]; then
      ${JAVA_HOME}/bin/keytool -genkey -alias jenkins_master -keyalg RSA -keystore ${JENKINS_HOME}/jenkins_keystore.jks -storepass ${JENKINS_KEYSTORE_PASSWORD} -keypass ${JENKINS_KEYSTORE_PASSWORD} --dname "${JENKINS_CERTIFICATE_DNAME}"
    fi
    jenkins_parameters=${jenkins_parameters}' --httpPort=-1 --httpsPort=8080 --httpsKeyStore='${JENKINS_HOME}'/jenkins_keystore.jks --httpsKeyStorePassword='${JENKINS_KEYSTORE_PASSWORD}
  fi

  log_parameter=""

  if [ -n "${JENKINS_LOG_FILE}" ]; then
    log_dir=$(dirname ${JENKINS_LOG_FILE})
    log_file=$(basename ${JENKINS_LOG_FILE})
    if [ ! -d "${log_dir}" ]; then
      mkdir -p ${log_dir}
    fi
    if [ ! -f "${JENKINS_LOG_FILE}" ]; then
      touch ${JENKINS_LOG_FILE}
    fi
    log_parameter=" --logfile="${JENKINS_LOG_FILE}
  fi

  unset JENKINS_ADMIN_USER
  unset JENKINS_ADMIN_PASSWORD
  unset JENKINS_KEYSTORE_PASSWORD
  unset SMTP_USER_NAME
  unset SMTP_USER_PASS

  # Start jenkins
  exec /usr/bin/java -Dfile.encoding=UTF-8 -Djenkins.install.runSetupWizard=false ${java_vm_parameters} -jar /usr/bin/jenkins/jenkins.war ${jenkins_parameters}${log_parameter}
elif [[ "$1" == '--'* ]]; then
  # Run Jenkins with passed parameters.
  exec /usr/bin/java -Dfile.encoding=UTF-8 -Djenkins.install.runSetupWizard=false ${java_vm_parameters} -jar /usr/bin/jenkins/jenkins.war "$@"
else
  exec "$@"
fi
