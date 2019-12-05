import boto3
import uuid
import time


ec2 = boto3.resource('ec2')


def buildWorkerImages(userdataPath):
  with open(userdataPath, 'r') as userdataFile:
    userdata = userdataFile.read()
  instances = ec2.create_instances(
    BlockDeviceMappings = [{ 'DeviceName': '/dev/sda1', 'Ebs': { 'DeleteOnTermination': True, 'VolumeSize': 40, 'VolumeType': 'gp2' }}, { 'DeviceName': '/dev/sdb', 'Ebs': { 'DeleteOnTermination': True, 'VolumeSize': 120, 'VolumeType': 'gp2' }}],
    ImageId = 'ami-0d5ab31b93c643ca8',
    InstanceType = 'c5.4xlarge',
    SecurityGroupIds = ['sg-3bd7bf41'],
    SubnetId = 'subnet-f94cb29f',
    UserData = userdata,
    ClientToken = str(uuid.uuid4()),
    IamInstanceProfile = { 'Arn': 'arn:aws:iam::692406183521:instance-profile/windows-ami-builder' },
    InstanceInitiatedShutdownBehavior = 'stop',
    MaxCount = 1,
    MinCount = 1,
    KeyName = 'mozilla-taskcluster-worker-relops-image-builder')

  instance = ec2.Instance(instances[0].id)
  while instance.state['Name'] not in ('stopped'):
    print('info: awaiting stopped state for instance: {} in state: {}'.format(instance.id, instance.state['Name']))
    time.sleep(30)
    instance.load()
  print('info: detected {} state for instance {}'.format(instance.state['Name'], instance.id))
  image = instance.create_image(
    Name = 'relops-image-builder',
    Description = 'taskcluster windows image builder',
    NoReboot = True
  )
  print('info: awaiting available state for image {}'.format(image.id))
  while image.state not in ('available'):
    print('info: awaiting available state for image: {} in state: {}'.format(image.id, image.state))
    time.sleep(30)
    image.load()
  print('info: detected {} state for image {}'.format(image.state, image.id))


buildWorkerImages('ci/config/.userdata')