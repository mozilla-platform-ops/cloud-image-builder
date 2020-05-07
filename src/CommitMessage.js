import React from 'react';
import Badge from 'react-bootstrap/Badge';

class CommitMessage extends React.Component {
  state = {
    isPoolDeploy: false,
    include: {
      environments: [],
      keys: [],
      pools: [],
      regions: []
    },
    exclude: {
      environments: [],
      integrations: [],
      keys: [],
      pools: [],
      regions: []
    }
  };
  componentDidMount() {
    this.setState(state => ({
      isPoolDeploy: this.props.message.some(line => line === 'pool-deploy'),
      include: {
        environments: [
          ...(this.props.message.some(line => line.startsWith('include environments: ')) ? this.props.message.find(line => line.startsWith('include environments: ')).replace('include environments: ', '').split(', ') : [])
        ],
        keys: [
          ...(this.props.message.some(line => line.startsWith('include keys: ')) ? this.props.message.find(line => line.startsWith('include keys: ')).replace('include keys: ', '').split(', ') : [])
        ],
        pools: [
          ...(this.props.message.some(line => line.startsWith('include pools: ')) ? this.props.message.find(line => line.startsWith('include pools: ')).replace('include pools: ', '').split(', ') : [])
        ],
        regions: [
          ...(this.props.message.some(line => line.startsWith('include regions: ')) ? this.props.message.find(line => line.startsWith('include regions: ')).replace('include regions: ', '').split(', ') : [])
        ]
      },
      exclude: {
        environments: [
          ...(this.props.message.some(line => line.startsWith('exclude environments: ')) ? this.props.message.find(line => line.startsWith('exclude environments: ')).replace('exclude environments: ', '').split(', ') : [])
        ],
        integrations: [
          ...((this.props.message.some(line => line === 'no-ci') || (this.props.message.some(line => line === 'no-taskcluster-ci'))) ? ['taskcluster'] : []),
          ...((this.props.message.some(line => line === 'no-ci') || (this.props.message.some(line => line === 'no-travis-ci'))) ? ['taskcluster'] : [])
        ],
        keys: [
          ...(this.props.message.some(line => line.startsWith('exclude keys: ')) ? this.props.message.find(line => line.startsWith('exclude keys: ')).replace('exclude keys: ', '').split(', ') : [])
        ],
        pools: [
          ...(this.props.message.some(line => line.startsWith('exclude pools: ')) ? this.props.message.find(line => line.startsWith('exclude pools: ')).replace('exclude pools: ', '').split(', ') : [])
        ],
        regions: [
          ...(this.props.message.some(line => line.startsWith('exclude regions: ')) ? this.props.message.find(line => line.startsWith('exclude regions: ')).replace('exclude regions: ', '').split(', ') : [])
        ]
      }
    }));
  }
  render() {
    return (
      <div>
        {
          this.props.message.filter(l => (
            l !== 'no-ci'
            && l !== 'no-taskcluster-ci'
            && l !== 'no-travis-ci'
            && !l.startsWith('exclude environments: ')
            && !l.startsWith('include environments: ')
            && !l.startsWith('exclude keys: ')
            && !l.startsWith('include keys: ')
            && !l.startsWith('exclude pools: ')
            && !l.startsWith('include pools: ')
            && !l.startsWith('exclude regions: ')
            && !l.startsWith('include regions: ')
          )).map(line => (
            <span>
              {line}
              <br />
            </span>
          ))
        }
        {
          ['include', 'exclude'].map(inex => (
            ['environments', 'integrations', 'keys', 'pools', 'regions'].map(type => (
              this.props.message.filter(line => line.startsWith(inex + ' ' + type + ': ')).map(line => (
                line.replace(inex + ' ' + type + ': ', '').split(', ').map(item => (
                  <Badge style={{ margin: '0 1px' }} variant={(inex === 'include') ? 'light' : 'dark'}>
                    {inex + ' ' + type.replace('s', '') + ': ' + item}
                  </Badge>
                ))
              ))
            ))
          ))
        }
      </div>
    );
  }
}

export default CommitMessage;
