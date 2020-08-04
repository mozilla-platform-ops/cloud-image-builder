import React from 'react';
import Badge from 'react-bootstrap/Badge';
import { DashCircleFill, PlusCircleFill } from 'react-bootstrap-icons';

class CommitMessage extends React.Component {
  render() {
    return (
      <div>
        {
          this.props.message.filter(line => (
            !line.match((new RegExp ('^(include|exclude) (environment|key|pool|region)s: .*$', 'i')))
            &&
            !line.match((new RegExp ('^(pool-deploy|overwrite-disk-image|overwrite-machine-image|disable-cleanup|purge-taskcluster-resources|no-ci|no-taskcluster-ci|no-travis-ci)$', 'i')))
          )).map((line, lI) => (
            (lI === 0)
              ? (line.match(/bug ([0-9]{5,8})/i)) ? <span key={lI}><a href={'https://bugzilla.mozilla.org/show_bug.cgi?id=' + line.match(/bug ([0-9]{5,8})/i)[1] } target="_blank" rel="noopener noreferrer">{line.match(/bug ([0-9]{5,8})/i)[0]}</a> {line.replace(line.match(/bug ([0-9]{5,8})/i)[0], '')}<br /></span> : <strong key={lI}>{line}<br /></strong>
              : (line.match(/bug ([0-9]{5,8})/i)) ? <span key={lI}><a href={'https://bugzilla.mozilla.org/show_bug.cgi?id=' + line.match(/bug ([0-9]{5,8})/i)[1] } target="_blank" rel="noopener noreferrer">{line.match(/bug ([0-9]{5,8})/i)[0]}</a> {line.replace(line.match(/bug ([0-9]{5,8})/i)[0], '')}<br /></span> : <span key={lI}>{line}<br /></span>
          ))
        }
        {
          (this.props.message.some(line => (
            line.match(/^(include|exclude) (environment|key|pool|region)s: .*$/i)
            ||
            line.match(/^(pool-deploy|overwrite-disk-image|overwrite-machine-image|disable-cleanup|purge-taskcluster-resources|no-ci|no-taskcluster-ci|no-travis-ci)$/i)
          )))
            ? (
                (this.props.message.filter(line => (line.match(/^(pool-deploy|overwrite-disk-image|overwrite-machine-image|disable-cleanup|purge-taskcluster-resources|no-ci|no-taskcluster-ci|no-travis-ci)$/i)))).map(instruction => (
                  <Badge
                    key={instruction}
                    style={{ marginRight: '0.7em' }}
                    variant={(['pool-deploy', 'overwrite-disk-image', 'overwrite-machine-image', 'disable-cleanup', 'purge-taskcluster-resources'].includes(instruction)) ? 'primary' : 'dark'}>
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
                  <span key={inex}>
                    {
                      ['environments', 'integrations', 'keys', 'pools', 'regions'].map(type => (
                        this.props.message.filter(line => line.startsWith(inex + ' ' + type + ': ')).map((line, lI) => (
                          line.replace(inex + ' ' + type + ': ', '').split(', ').map(item => (
                            <Badge
                              key={lI}
                              style={{ marginRight: '0.7em' }}
                              variant={(inex === 'include') ? 'info' : 'dark'}
                              title={inex + ' ' + type.slice(0, -1) + ': ' + item}>
                              {
                                (inex === 'include')
                                  ? <PlusCircleFill />
                                  : <DashCircleFill />
                              }
                              &nbsp;{item}
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
