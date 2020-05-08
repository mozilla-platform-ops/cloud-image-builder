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
          this.props.message.filter(line => (
            !line.match((new RegExp ('^(include|exclude) (environment|key|pool|region)s: .*$', 'i')))
            &&
            !line.match((new RegExp ('^(pool-deploy|no-ci|no-taskcluster-ci|no-travis-ci)$', 'i')))
          )).map(line => (
            <strong>
              {line}<br />
            </strong>
          ))
        }
        {
          (this.props.message.some(line => (
            line.match(/^(include|exclude) (environment|key|pool|region)s: .*$/i)
            ||
            line.match(/^(pool-deploy|no-ci|no-taskcluster-ci|no-travis-ci)$/i)
          )))
            ? (
                (this.props.message.filter(line => (line.match(/^(pool-deploy|no-ci|no-taskcluster-ci|no-travis-ci)$/i)))).map(instruction => (
                  <Badge style={{ margin: '0 4px 0 0' }} variant={(instruction == 'pool-deploy') ? 'primary' : 'dark'}>
                    {instruction}
                  </Badge>
                ))
              )
            : (
                <Badge variant="warning">
                  no commit syntax ci instructions
                </Badge>
              )
        }
        {
          ['include', 'exclude'].map(inex => (
            (this.props.message.some(line => line.match((new RegExp ('^' + inex + ' (environment|key|pool|region)s: .*$', 'i')))))
              ? (
                  <span>
                    {
                      ['environments', 'integrations', 'keys', 'pools', 'regions'].map(type => (
                        this.props.message.filter(line => line.startsWith(inex + ' ' + type + ': ')).map(line => (
                          line.replace(inex + ' ' + type + ': ', '').split(', ').map(item => (
                            <Badge style={{ margin: '0 4px 0 0', textDecoration: (inex === 'include') ? 'none' : 'line-through' }} variant={(inex === 'include') ? 'info' : 'warning'}>
                              {item}
                            </Badge>
                          ))
                        ))
                      ))
                    }
                    <br />
                  </span>
                )
              : ''
          ))
        }
      </div>
    );
  }
}

export default CommitMessage;
