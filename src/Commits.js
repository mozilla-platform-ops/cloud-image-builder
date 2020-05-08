import React from 'react'
import Commit from './Commit';
import Accordion from 'react-bootstrap/Accordion';

class Commits extends React.Component {
  /*
  constructor(props) {
    super(props);
    this.state = {
      defaultActiveKey: props.latest
    };
  }
  componentDidMount() {
    this.setState(state => ({ defaultActiveKey: (this.props.commits && this.props.commits.length) ? this.props.commits[0].sha : null }));
  }
  */
  render() {
    return (
      <Accordion defaultActiveKey={null/*this.props.latest*/}>
        {
          this.props.commits.map(commit => (
            <Commit commit={commit} key={commit.sha} expand={false/*(commit.sha === this.props.latest)*/} />
          ))
        }
      </Accordion>
    );
  }
}

export default Commits;
