import React from 'react'
import Status from './Status';

class Statuses extends React.Component {
  render() {
    return (
      <ul>
        {
          this.props.contexts.map((context, cI) => (
            <li key={cI}>
              { context }
              <ul>
              {
                this.props.statuses.filter(s => s.context === context).map((status) => (
                  <Status status={status} key={status.id} />
                ))
              }
              </ul>
            </li>
          ))
        }
      </ul>
    );
  }
}

export default Statuses;
