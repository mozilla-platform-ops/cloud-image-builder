import React from 'react'
import Commit from './Commit';

class Commits extends React.Component {
  render() {
    return (
      <ul style={{
        listStyle: 'none',
        marginLeft: '0',
        paddingLeft: '0'
      }}>
        {
          this.props.commits.map(commit => (
            <Commit commit={commit} key={commit.sha} />
          ))
        }
      </ul>
    );
  }
}

export default Commits;
