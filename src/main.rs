use argparse::{ArgumentParser, StoreTrue, Store};
use rslnp::Parser as ScopesParser;
use token_parser::Parser;
use std::fs;
use std::fmt;
use std::process::Command;
use std::str;

pub type Result<T> = std::result::Result<T, token_parser::Error>;

#[derive(Debug)]
enum List {
    Sym(String),
    List(Vec<List>),
}

impl token_parser::Parsable<()> for List {
    fn parse_list(parser: &mut Parser, _context: &()) -> Result<Self> {
        let result : Vec<List> = parser.parse_list(&())?;
        Ok(List::List(result))
    }
    fn parse_symbol(name: String, _context: &()) -> Result<Self> {
        Ok(List::Sym(name))
    }
}

impl fmt::Display for List {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            List::Sym(sym) => {
                write!(f, "{}", sym)?;
            },
            List::List(list) => { match &list[..] {
                    [List::Sym(y), List::Sym(x)] if y == "fsc-reserved-double-quote" => {
                        write!(f, "{:?}", x)?;
                    }
                    _ => {
                        write!(f, "(")?;
                        let len = list.len();
                        for (i, x) in list.iter().enumerate() {
                            write!(f, "{}", x)?;
                            if i != len-1 {
                                write!(f, " ")?;
                            }
                        }
                        write!(f, ")")?;
                    }
                }
            }
        }
        Ok(())
    }
}

fn infer_parens(input_path: &str) -> String {
    let parser = ScopesParser::new()
            .indent(4)
            .unpack_single(true)
            .with_strings('"', Some("fsc-reserved-double-quote".into()))
            .with_brackets('(', ')', None)
            .with_brackets('[', ']', Some("fsc-reserved-square-bracket".into()))
            .with_brackets('{', '}', Some("fsc-reserved-curly-bracket".into()))
            .with_comments('#')
            .with_separator(';')
            .with_symbol_character(',')
            .allow_multi_indent(true);

    let content = fs::read_to_string(input_path).unwrap();
    let mut parsed: Vec<List> = parser.parse(content.chars()).unwrap().parse_rest(&()).unwrap();
    parsed.insert(0, List::Sym("do".to_owned()));
    let mut string = List::List(parsed).to_string();
    unsafe {
        let bytes = string.as_bytes_mut();
        for x in bytes.iter_mut() {
            if *x == 64 {
                *x = 46;
            }
        }
    }
format!("{} (macrodebug (process {})) \"\"", include_str!("macro.fnl"), string)
}


fn to_utf8(arg: &std::process::Output) -> &str {
    if arg.status.code() != Some(0) {
        panic!("{}", str::from_utf8(arg.stderr.as_slice()).unwrap());
    }
    str::from_utf8(arg.stdout.as_slice()).unwrap()
}

fn main() {
    let mut input_path = "".to_string();
    let mut to_fnl = false;

    {
        let mut ap = ArgumentParser::new();
        ap.set_description("compile an fsc file");
        ap.refer(&mut input_path)
            .add_argument("input", Store,
            "The path to the file to be compiled")
            .required();
        ap.refer(&mut to_fnl)
            .add_option(&["-f", "--fennel"], StoreTrue,
            "If this flag is present, compile to fennel instead of lua");
        ap.parse_args_or_exit();
    }

    let macro_source = infer_parens(&input_path);
    let output = Command::new("fennel").args(["--eval", &macro_source]).output().unwrap();
    let fennel_source = str::trim(to_utf8(&output));
    if to_fnl {
        println!("{}", fennel_source);
    } else {
        let output = Command::new("mktemp").output().unwrap();
        let path = str::trim(to_utf8(&output));
        fs::write(path, fennel_source).unwrap();
        let output = &Command::new("fennel").args(["--compile", path]).output().unwrap();
        let lua_source = to_utf8(&output);
        println!("{}", lua_source);

    }
}
