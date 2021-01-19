#!/bin/bash

sudo -i

echo "Installing git..."
yum -y install git
echo "Git installed."

su ssm-user
cd /home/ssm-user

echo "Configuring git credentials..."

cat >> git-askpass-helper.sh << EOF
#!/bin/sh
exec echo "${PASSWORD}"
EOF

chown ssm-user:ssm-user git-askpass-helper.sh
chmod 500 git-askpass-helper.sh
export GIT_ASKPASS=/home/ssm-user/git-askpass-helper.sh

git config --system credential.helper cache
git config --system user.name ${USERNAME}
git config --system user.password ${PASSWORD}
echo "Git credentials configured"

echo "Installing Terraform version ${TERRAFORM_VERSION}..."
wget https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip
unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip
mv terraform /usr/local/bin
echo "Terraform installed."
