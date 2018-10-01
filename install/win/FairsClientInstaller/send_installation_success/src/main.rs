extern crate reqwest;

fn main() -> Result<(), reqwest::Error> {
    let client = reqwest::Client::new();
    let result = client
        .post("https://www.mos.ru/blockchain-yarmarki/installed?q=InstallationCompleted")
        .body("Installation completed")
        .send()?;
    println!("{:?}", result);
    Ok(())
}
