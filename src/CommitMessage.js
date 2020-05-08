import React from 'react';
import Badge from 'react-bootstrap/Badge';

class CommitMessage extends React.Component {
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
