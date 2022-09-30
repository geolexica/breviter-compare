require('@tensorflow/tfjs');
const use = require('@tensorflow-models/universal-sentence-encoder');
const fs = require('fs');

// array of sentences to parse
const filename = process.argv.slice(2)[0];

console.log('Arguments: ', filename);
console.log("Starting ...")

try {
  // Load the model.
  console.log("  Loading model ...")
  use.load().then(model => {
    console.log("  Reading Input file ...")
    const data = fs.readFileSync(filename, 'utf8');

    let query_texts = [];
    let expected_results = [];

    let text, result;

    console.log("  Generating queries ...")
    let lines = data.split(/\r?\n/);
    for (const line of lines) {
      [text, result] = line.split(";")

      query_texts.push(text);
      expected_results.push(result);
    }

    console.log("  Loading Embeddings ...")
    model.embed(query_texts).then(embeddings => {
      // `embeddings` is a 2D tensor consisting of the 512-dimensional embeddings for each sentence.
      // So in this example `embeddings` has the shape [2, 512].
      // embeddings.print(true /* verbose */);

      console.log("  Embeddings Loaded, Generating output ...")
      let output = embeddings.arraySync().map(function(vector, i){
        return [query_texts[i], expected_results[i], vector]
      });

      console.log("  Writing to file ...")
      fs.writeFile('test-vectors.txt', JSON.stringify(output), err => {
        if (err) {
          console.error(err);
        }
        // file written successfully
        console.log("Done.")
      });
    });
  });
} catch (err) {
  console.error(err);
}
