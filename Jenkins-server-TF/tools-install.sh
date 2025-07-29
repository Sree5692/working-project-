#!/bin/bash
# For Ubuntu 22.04

# --- Java Installation ---
sudo apt update -y
sudo apt install openjdk-17-jre -y
sudo apt install openjdk-17-jdk -y
java --version

# --- Owasp DP-Check ---
cd /opt
sudo mkdir -p owasp-dc
cd owasp-dc
wget https://github.com/jeremylong/DependencyCheck/releases/download/v8.4.0/dependency-check-8.4.0-release.zip
unzip dependency-check-8.4.0-release.zip

# --- Jenkins Installation ---
curl -fsSL https://pkg.jenkins.io/debian/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt-get update -y
sudo apt-get install jenkins -y

# --- Jenkins Initial Configuration (Groovy Script Automation) ---
sudo mkdir -p /var/lib/jenkins/init.groovy.d

sudo bash -c "cat << 'EOF' > /var/lib/jenkins/init.groovy.d/basic-setup.groovy
import jenkins.model.*
import hudson.security.*
import jenkins.install.InstallState
import com.cloudbees.plugins.credentials.impl.*
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.*
import com.cloudbees.jenkins.plugins.awscredentials.AWSCredentialsImpl
import org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl
import hudson.util.Secret
import hudson.model.JDK
import hudson.plugins.sonar.SonarRunnerInstallation
import jenkins.plugins.nodejs.tools.NodeJSInstallation
import jenkins.plugins.nodejs.tools.NodeJSInstaller
import org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation
import hudson.plugins.sonar.SonarGlobalConfiguration
import hudson.plugins.sonar.SonarInstallation

// ---- CREATE ADMIN USER ----
def instance = Jenkins.getInstance()
def hudsonRealm = new HudsonPrivateSecurityRealm(false)
if (hudsonRealm.getAllUsers().size() == 0) {
    hudsonRealm.createAccount('sree', 'sree123')
    instance.setSecurityRealm(hudsonRealm)
}
instance.setInstallState(InstallState.INITIAL_SETUP_COMPLETED)

// ---- INSTALL PLUGINS ----
def pluginParameter = [
    'git',
    'temurin',
    'sonar',
    'nodejs',
    'docker-plugin',
    'docker-commons',
    'docker-workflow',
    'docker-api',
    'docker-build-step',
    'dependency-check-jenkins-plugin',
    'terraform',
    'aws-credentials',
    'pipeline-aws',
    'prometheus'
]
def pm = instance.getPluginManager()
def uc = instance.getUpdateCenter()
pluginParameter.each {
    if (!pm.getPlugin(it)) {
        def plugin = uc.getPlugin(it)
        if (plugin) {
            plugin.deploy()
        }
    }
}
instance.save()

// ---- ADD CREDENTIALS ----
def credentials_store = Jenkins.instance.getExtensionList('com.cloudbees.plugins.credentials.SystemCredentialsProvider')[0].getStore()

// 1. Docker Hub (Username/Password)
def dockerCreds = new UsernamePasswordCredentialsImpl(
    CredentialsScope.GLOBAL,
    "docker",
    "docker hub credentials for pipeline",
    "sree56",
    "56Spirit@power92"
)
credentials_store.addCredentials(Domain.global(), dockerCreds)

// 2. Github Personal Access Token (Secret Text)
def githubToken = new StringCredentialsImpl(
    CredentialsScope.GLOBAL,
    "githubcred",
    "Github Personal Access Token",
    Secret.fromString("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")
)
credentials_store.addCredentials(Domain.global(), githubToken)

// 3. AWS Credentials (Access Key & Secret)
def awsCreds = new AWSCredentialsImpl(
    CredentialsScope.GLOBAL,
    "aws-key",
    "aws credentials for pipeline",
    "AKIA6ODU626LHI445GIA",
    "LhA0FD77kzadGiOwf4znJ7vkqRZExxBV4Z5catlT"
)
credentials_store.addCredentials(Domain.global(), awsCreds)

// 4. SonarQube Token (Secret Text placeholder, replace manually after first run)
def sonarToken = new StringCredentialsImpl(
    CredentialsScope.GLOBAL,
    "sonar-token",
    "SonarQube Authentication Token",
    Secret.fromString("REPLACE_WITH_REAL_TOKEN")
)
credentials_store.addCredentials(Domain.global(), sonarToken)

// ------ Global Tool Installations ------

// JDK Installation
def jdkDesc = new JDK.DescriptorImpl()
def jdkInstall = new JDK("jdk", "/usr/lib/jvm/java-17-openjdk-amd64")
jdkDesc.setInstallations(jdkInstall)
jdkDesc.save()

// SonarQube Scanner Installation (auto-install default version)
def sonarRunnerDesc = Jenkins.instance.getDescriptorByType(SonarRunnerInstallation.DescriptorImpl.class)
def sonarInstall = new SonarRunnerInstallation("sonar-scanner", "", [new hudson.plugins.sonar.SonarRunnerInstaller(null)])
sonarRunnerDesc.setInstallations(sonarInstall)
sonarRunnerDesc.save()

// NodeJS Installation (auto-install default version)
def nodejsDesc = Jenkins.instance.getDescriptorByType(NodeJSInstallation.DescriptorImpl.class)
def nodejsInstall = new NodeJSInstallation("nodejs", "", [new NodeJSInstaller(null, "", false)])
nodejsDesc.setInstallations(nodejsInstall)
nodejsDesc.save()

// Dependency-Check Installation
def dcDesc = Jenkins.instance.getDescriptorByType(org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation.DescriptorImpl.class)
def dcInstall = new DependencyCheckInstallation("DP-Check", "/opt/owasp-dc/dependency-check", [])
dcDesc.setInstallations(dcInstall)
dcDesc.save()

// ------ SonarQube Server Configuration ------
def sonarConfig = Jenkins.instance.getDescriptorByType(hudson.plugins.sonar.SonarGlobalConfiguration.class)
def sonarServer = new SonarInstallation(
    "sonar-server",
    "http://44.213.89.155:9000/",
    "sonar-token", // references the credentials ID above
    "",
    "",
    null,
    false
)
sonarConfig.setInstallations(sonarServer)
sonarConfig.save()
EOF"

sudo chown -R jenkins:jenkins /var/lib/jenkins/init.groovy.d/
sudo systemctl restart jenkins

# --- Docker Installation ---
sudo apt update
sudo apt install docker.io -y
sudo usermod -aG docker jenkins
sudo usermod -aG docker ubuntu
sudo systemctl restart docker
sudo chmod 777 /var/run/docker.sock

# --- SonarQube in Docker ---
docker run -d --name sonar -p 9000:9000 sonarqube:lts-community

# --- AWS CLI Installation ---
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
sudo apt install unzip -y
unzip awscliv2.zip
sudo ./aws/install

# --- Kubectl Installation ---
sudo apt update
sudo apt install curl -y
sudo curl -LO "https://dl.k8s.io/release/v1.28.4/bin/linux/amd64/kubectl"
sudo chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client

# --- Terraform Installation ---
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update
sudo apt install terraform -y

# --- Trivy Installation ---
sudo apt-get install wget apt-transport-https gnupg lsb-release -y
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
echo deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main | sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt update
sudo apt install trivy -y
