import boto3
import slugid
import time
import uuid


def buildWorkerImages(userdataPath, buildRegion, copyRegions):
    ec2Resource = boto3.Session(region_name = buildRegion).resource('ec2')
    with open(userdataPath, 'r') as userdataFile:
        userdata = userdataFile.read()
    instances = ec2Resource.create_instances(
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

    instance = ec2Resource.Instance(instances[0].id)
    while instance.state['Name'] not in ('stopped'):
        print('info: awaiting stopped state for instance: {}/{} in state: {}'.format(buildRegion, instance.id, instance.state['Name']))
        time.sleep(30)
        instance.load()
    print('info: detected {} state for instance {}/{}'.format(instance.state['Name'], buildRegion, instance.id))
    image = instance.create_image(
        Name = 'relops-image-builder-{}'.format(slugid.nice()),
        Description = 'taskcluster windows image builder',
        NoReboot = True
    )
    print('info: awaiting available state for image {}/{}'.format(buildRegion, image.id))
    while image.state not in ('available'):
        print('info: awaiting available state for image: {}/{} in state: {}'.format(buildRegion, image.id, image.state))
        time.sleep(30)
        image.load()
    print('info: detected {} state for image {}/{}'.format(image.state, buildRegion, image.id))

    copiedImages = []
    imageRegionMap = {}
    for copyRegion in copyRegions:
        ec2RegionClient = boto3.client('ec2', region_name = copyRegion)
        imageCopyResponse = ec2RegionClient.copy_image(
            ClientToken = slugid.nice(),
            Description = image.description,
            Name = image.name,
            SourceImageId = image.id,
            SourceRegion = buildRegion
        )
        copiedImage = boto3.Session(region_name = copyRegion).resource('ec2').Image(imageCopyResponse['ImageId'])
        copiedImages.append(copiedImage)
        imageRegionMap[copiedImage.id] = copyRegion

    while any(i.state not in ('available') for i in copiedImages):
        for copiedImage in copiedImages:
            if copiedImage.state not in ('available'):
                print('info: awaiting available state for image: {}/{} in state: {}'.format(imageRegionMap[copiedImage.id], copiedImage.id, copiedImage.state))
                copiedImage.load()
            time.sleep(2)
    for copiedImage in copiedImages:
        print('info: detected {} state for image: {}/{}'.format(copiedImage.state, imageRegionMap[copiedImage.id], copiedImage.id))


buildWorkerImages(
    userdataPath = 'ci/config/.userdata',
    buildRegion = 'us-west-2',
    copyRegions = ['us-east-1', 'us-east-2', 'us-west-1', 'eu-central-1'])